defmodule TcmEdu.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.

  `bin/migrate` runs the full flow (对齐 `mix tcm_edu.migrate`)：

    1. public schema Ecto migrations（含 organizations / super_admins /
       audit_logs / api_key_configs / tokens）
    2. ensure 默认租户 `tenant_default`（不存在则建 schema）
    3. 为所有 `tenant_*` schema 跑租户迁移（users / courses / enrollments /
       quiz / notifications）
  """

  @app :tcm_edu

  def migrate do
    load_app()
    start_repo()

    run_public_migrations()
    ensure_default_tenant()
    run_tenant_migrations()

    :ok
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  # ── public schema migrations ──────────────────────────────

  defp run_public_migrations do
    require Logger

    for repo <- repos() do
      path = Application.app_dir(@app, "priv/repo/migrations")
      Logger.info("Running public migrations for #{inspect(repo)} from #{path}")
      _ = Ecto.Migrator.run(repo, path, :up, all: true)
    end
  end

  # ── 默认租户 ──────────────────────────────────────────────

  defp ensure_default_tenant do
    require Logger
    require Ash.Query

    alias TcmEdu.System.Organization

    case Organization
         |> Ash.Query.filter(slug == "default")
         |> Ash.read_one(authorize?: false) do
      {:ok, %Organization{} = org} ->
        Logger.info("Default tenant exists: #{org.schema_name} (#{org.id})")
        :ok

      {:ok, nil} ->
        case Organization
             |> Ash.Changeset.for_action(:create_with_schema, %{
               name: "Default tenant (system)",
               slug: "default",
               contact_email: "admin@example.com",
               description: "由 TcmEdu.Release.migrate 自动创建的默认租户"
             })
             |> Ash.create(authorize?: false) do
          {:ok, %Organization{} = org} ->
            Logger.info("Default tenant created: #{org.schema_name} (#{org.id})")
            :ok

          {:error, error} ->
            raise "Failed to create default tenant: #{inspect(error)}"
        end

      {:error, reason} ->
        raise "Failed to query default tenant: #{inspect(reason)}"
    end
  end

  # ── tenant migrations ─────────────────────────────────────

  defp run_tenant_migrations do
    require Logger

    case TcmEdu.TenantProvisioning.run_migrations_for_all_tenants() do
      :ok -> :ok
      {:error, failures} -> raise "Tenant migrations failed: #{inspect(failures)}"
    end
  end

  # ── infra ─────────────────────────────────────────────────

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
    # Ash/AshPostgres 链需要启动（保证数据层可用），不启动整个应用
    Application.ensure_all_started(:ash)
    Application.ensure_all_started(:ash_postgres)
  end

  defp start_repo do
    case TcmEdu.Repo.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} -> raise "Failed to start Repo: #{inspect(reason)}"
    end
  end
end
