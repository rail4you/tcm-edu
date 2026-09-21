defmodule TcmEdu.Repo.Migrations.CreateAuditLogsAndApiKeyConfigs do
  @moduledoc """
  public schema 迁移：操作日志 + AI Provider Key 配置。

  * `audit_logs`     — 跨租户审计日志（tenant 列标识所属租户）
  * `api_key_configs`— AI Provider key（provider 唯一）
  """

  use Ecto.Migration

  def up do
    create table(:audit_logs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :tenant, :string, null: true
      add :actor_id, :uuid, null: true
      add :action, :string, null: false
      add :resource_type, :string, null: true
      add :resource_id, :uuid, null: true
      add :changes, :jsonb, null: false, default: "{}"
      add :ip, :string, null: true
      add :user_agent, :string, null: true
      add :success, :boolean, null: false, default: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:audit_logs, [:tenant], name: "audit_logs_tenant_index")
    create index(:audit_logs, [:action], name: "audit_logs_action_index")
    create index(:audit_logs, [:actor_id], name: "audit_logs_actor_index")

    create table(:api_key_configs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :provider, :string, null: false
      add :api_key, :text, null: false
      add :base_url, :string, null: true
      add :model, :string, null: true
      add :is_active, :boolean, null: false, default: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    # 对齐 Ash identity `unique_provider` 命名，避免唯一冲突当 500
    create unique_index(:api_key_configs, [:provider],
             name: "api_key_configs_unique_provider_index"
           )
  end

  def down do
    drop_if_exists table(:api_key_configs)
    drop_if_exists table(:audit_logs)
  end
end
