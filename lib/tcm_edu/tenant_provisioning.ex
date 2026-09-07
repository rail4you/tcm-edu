defmodule TcmEdu.TenantProvisioning do
  @moduledoc """
  租户 provisioning：建 schema + 跑迁移。

  被 `TcmEdu.System.Organization.create_with_schema` 的
  `after_action` 钩子调用。也单独暴露给 `mix tcm_edu.provision` 任务。

  ## 步骤

    1. `CREATE SCHEMA IF NOT EXISTS <schema_name>`
    2. 在该 schema 上跑 `priv/repo/tenant_migrations/*.exs`
    3. 返回 `{:ok, ...}` 或 `{:error, ...}`

  ## 失败处理

  如果步骤 2 失败，schema 已建但表没建完——下次再调用会重跑迁移
  （因为 `schema_migrations` 表为空），所以是幂等的。如果想完全回滚，
  调用方应随后 `DROP SCHEMA … CASCADE`。
  """

  require Logger

  alias TcmEdu.Repo
  alias TcmEdu.System.Organization

  @tenant_migrations_path "priv/repo/tenant_migrations"

  @doc """
  Provisioning 一个租户：建 schema + 跑迁移。
  """
  @spec provision_tenant(%Organization{}) :: :ok | {:error, term()}
  def provision_tenant(%Organization{schema_name: schema_name} = org)
      when is_binary(schema_name) do
    Logger.info("Provisioning tenant: #{schema_name} (#{org.slug})")

    with :ok <- create_schema(schema_name),
         :ok <- run_tenant_migrations(schema_name),
         :ok <- seed_default_admin(org) do
      Logger.info("Tenant #{schema_name} provisioned successfully")
      :ok
    end
  end

  def provision_tenant(%Organization{schema_name: nil} = org) do
    {:error, "Organization #{org.id} has no schema_name; was create_with_schema called?"}
  end

  @doc """
  列出所有租户 schema（用于 `mix tcm_edu.migrate`）。
  """
  @spec all_tenant_schemas() :: [String.t()]
  def all_tenant_schemas do
    case Repo.query("SELECT nspname FROM pg_namespace WHERE nspname LIKE 'tenant_%' ORDER BY nspname") do
      {:ok, %{rows: rows}} -> Enum.map(rows, fn [n] -> n end)
      {:error, reason} -> raise "Failed to list tenant schemas: #{inspect(reason)}"
    end
  end

  @doc """
  为所有已存在的租户跑迁移。
  """
  @spec run_migrations_for_all_tenants() :: :ok | {:error, term()}
  def run_migrations_for_all_tenants do
    schemas = all_tenant_schemas()

    Logger.info("Running tenant migrations for #{length(schemas)} schema(s)")

    results =
      Enum.map(schemas, fn schema ->
        case run_tenant_migrations(schema) do
          :ok -> {:ok, schema}
          {:error, reason} -> {:error, schema, reason}
        end
      end)

    failures = Enum.filter(results, &match?({:error, _, _}, &1))

    case failures do
      [] -> :ok
      _ -> {:error, failures}
    end
  end

  # ── private ────────────────────────────────────────────────────────

  defp create_schema(schema_name) do
    case Repo.query("CREATE SCHEMA IF NOT EXISTS \"#{schema_name}\"") do
      {:ok, _} ->
        :ok

      {:error, %Postgrex.Error{} = err} ->
        {:error, "Failed to create schema #{schema_name}: #{Exception.message(err)}"}

      {:error, reason} ->
        {:error, "Failed to create schema #{schema_name}: #{inspect(reason)}"}
    end
  end

  defp run_tenant_migrations(schema_name) do
    path = tenant_migrations_path()

    unless File.dir?(path) do
      Logger.info("Creating tenant_migrations directory at #{path}")
      File.mkdir_p!(path)
      # 没有迁移文件时 Ecto.Migrator.run 会无事可做
    end

    Ecto.Migrator.with_repo(Repo, fn repo ->
      Ecto.Migrator.run(repo, path, :up, all: true, prefix: schema_name)
    end)
    |> case do
      {:ok, _, _} -> :ok
      {:error, reason} -> {:error, "Tenant migrations failed for #{schema_name}: #{inspect(reason)}"}
    end
  end

  # Phase 3 启用：在这个 hook 里创建第一个 tenant_admin 用户
  defp seed_default_admin(_org) do
    :ok
  end

  defp tenant_migrations_path do
    Application.get_env(:tcm_edu, :tenant_migrations_path, @tenant_migrations_path)
  end
end