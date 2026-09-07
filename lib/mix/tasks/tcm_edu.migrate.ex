defmodule Mix.Tasks.TcmEdu.Migrate do
  @moduledoc """
  TcmEdu 自定义迁移任务：

    1. 跑主迁移（public schema，含 `organizations`）
    2. 确保默认租户 `tenant_default` 存在（首次启动自动建）
    3. 为所有已存在的租户 schema 跑租户迁移

  用法：

      mix tcm_edu.migrate           # 全量迁移
      mix tcm_edu.migrate --tenants # 只跑租户迁移（已假定主迁移已跑过）
  """

  use Mix.Task

  alias TcmEdu.Repo
  alias TcmEdu.System.Organization
  alias TcmEdu.TenantProvisioning

  @default_slug "default"

  @shortdoc "跑主迁移 + 默认租户 + 所有租户迁移"

  @switches [tenants: :boolean, dry_run: :boolean]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    tenants_only? = Keyword.get(opts, :tenants, false)

    unless tenants_only? do
      run_main_migrations()
      ensure_default_tenant()
    end

    run_tenant_migrations()

    unless tenants_only? do
      migrate_legacy_users()
    end
  end

  defp run_main_migrations do
    Mix.shell().info("==> [1/3] 跑主迁移（public schema）...")

    Mix.Task.run("ash.migrate")
  end

  defp ensure_default_tenant do
    Mix.shell().info("==> [2/3] 确保默认租户存在...")

    require Ash.Query

    case Organization
         |> Ash.Query.filter(slug == @default_slug)
         |> Ash.read_one(authorize?: false) do
      {:ok, %Organization{} = org} ->
        Mix.shell().info("    ✓ 默认租户已存在: #{org.schema_name} (#{org.id})")

      {:ok, nil} ->
        create_default_tenant()

      {:error, reason} ->
        Mix.shell().error("    ✗ 查询默认租户失败: #{inspect(reason)}")
        raise "Failed to query default tenant"
    end
  end

  defp create_default_tenant do
    case Organization
         |> Ash.Changeset.for_action(:create_with_schema, %{
           name: "Default tenant (system)",
           slug: @default_slug,
           contact_email: "admin@example.com",
           description: "由 tcm_edu.migrate 自动创建的默认租户"
         })
         |> Ash.create(authorize?: false) do
      {:ok, %Organization{} = org} ->
        Mix.shell().info("    ✓ 默认租户已创建: #{org.schema_name} (#{org.id})")
        :ok

      {:error, error} ->
        Mix.shell().error("    ✗ 默认租户创建失败: #{inspect(error)}")
        raise "Failed to create default tenant"
    end
  end

  defp run_tenant_migrations do
    Mix.shell().info("==> [3/4] 跑所有租户 schema 的迁移...")

    case TenantProvisioning.run_migrations_for_all_tenants() do
      :ok ->
        :ok

      {:error, failures} ->
        Mix.shell().error("    ✗ 租户迁移失败: #{inspect(failures)}")
        raise "Tenant migrations failed"
    end
  end

  # Phase 3：把旧 public.users 数据搬到 tenant_default.users
  # （admin → tenant_admin；user → student），然后 drop public.users。
  defp migrate_legacy_users do
    Mix.shell().info("==> [4/4] 迁移旧 public.users → tenant_default.users...")

    case Repo.query("SELECT to_regclass('public.users') IS NOT NULL") do
      {:ok, %{rows: [[true]]}} ->
        copy_and_drop_users()

      {:ok, %{rows: [[false]]}} ->
        Mix.shell().info("    - public.users 不存在，跳过")

      {:error, reason} ->
        Mix.shell().error("    ✗ 检查 public.users 失败: #{inspect(reason)}")
        raise "Legacy user migration failed"
    end
  end

  defp copy_and_drop_users do
    sql = """
    INSERT INTO tenant_default.users (id, email, name, hashed_password, role, status, inserted_at, updated_at)
    SELECT id,
           email,
           split_part(email, '@', 1),
           hashed_password,
           CASE role
             WHEN 'admin' THEN 'tenant_admin'
             ELSE 'student'
           END,
           'active',
           inserted_at,
           updated_at
    FROM public.users
    ON CONFLICT (id) DO NOTHING
    """

    case Repo.query(sql) do
      {:ok, %{num_rows: n}} ->
        Mix.shell().info("    ✓ 复制了 #{n} 条 user 记录到 tenant_default")

        # 复制后，Drop public.users
        Repo.query("DROP TABLE public.users")
        Mix.shell().info("    ✓ 删除 public.users")

      {:error, reason} ->
        Mix.shell().error("    ✗ 复制失败: #{inspect(reason)}")
        raise "Legacy user migration failed"
    end
  end
end