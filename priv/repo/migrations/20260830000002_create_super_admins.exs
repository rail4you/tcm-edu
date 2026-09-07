defmodule TcmEdu.Repo.Migrations.CreateSuperAdmins do
  @moduledoc """
  创建 `super_admins` 表（public schema，跨租户超级管理员）。
  """

  use Ecto.Migration

  def up do
    create table(:super_admins, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :email, :citext, null: false
      add :name, :string, null: true
      add :hashed_password, :text, null: false
      add :last_login_at, :utc_datetime, null: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:super_admins, [:email], name: "super_admins_unique_email_index")
  end

  def down do
    drop_if_exists unique_index(:super_admins, [:email], name: "super_admins_unique_email_index")
    drop table(:super_admins)
  end
end