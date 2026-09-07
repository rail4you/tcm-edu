defmodule TcmEdu.Repo.Migrations.CreateOrganizations do
  @moduledoc """
  创建 `organizations` 表（public schema）。

  手动编写（不走 `mix ash.codegen`），因为这是新资源、对应的迁移还没
  自动生成。后续若改 Organization 字段，用 `mix ash.codegen --dev`。
  """

  use Ecto.Migration

  def up do
    create table(:organizations, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :schema_name, :string, null: true
      add :contact_email, :string, null: true
      add :contact_phone, :string, null: true
      add :description, :text, null: true
      add :logo_url, :string, null: true
      add :status, :string, null: false, default: "active"
      add :plan, :string, null: false, default: "free"
      add :expires_at, :utc_datetime, null: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:organizations, [:slug], name: "organizations_unique_slug_index")
    create index(:organizations, [:status], name: "organizations_status_index")
  end

  def down do
    drop_if_exists index(:organizations, [:status], name: "organizations_status_index")
    drop_if_exists unique_index(:organizations, [:slug], name: "organizations_unique_slug_index")
    drop table(:organizations)
  end
end