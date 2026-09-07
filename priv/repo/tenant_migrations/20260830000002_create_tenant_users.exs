defmodule TcmEdu.Repo.TenantMigrations.CreateTenantUsers do
  @moduledoc """
  租户域 `users` 表迁移。每个 `tenant_*` schema 都会跑一次。

  字段对齐 `TcmEdu.Accounts.User` 资源 + AshAuthentication 所需：
    * `email` (citext，唯一)
    * `hashed_password` (text)
    * `role` (text，约束: tenant_admin/teacher/student)
    * `status` (text，默认 active)
    * profile 字段：name、avatar_url、phone、bio、job_title、school、major
    * timestamps

  ## 命名约定

    所有租户表加 `tenant_` 前缀避免与 public schema 冲突。
    但 Users / Courses 这类核心表保留单名 `users`，因为 AshPostgres
    默认会通过 schema prefix 限定范围，不会与 public.users 混淆。
  """

  use Ecto.Migration

  def up do
    create table(:users, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :email, :citext, null: false
      add :name, :string, null: true
      add :avatar_url, :string, null: true
      add :phone, :string, null: true
      add :bio, :text, null: true
      add :job_title, :string, null: true
      add :school, :string, null: true
      add :major, :string, null: true
      add :hashed_password, :text, null: false
      add :role, :string, null: false, default: "student"
      add :status, :string, null: false, default: "active"

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:users, [:email], name: "tenant_users_unique_email_index")
    create index(:users, [:role], name: "tenant_users_role_index")
    create index(:users, [:status], name: "tenant_users_status_index")
  end

  def down do
    drop_if_exists index(:users, [:status], name: "tenant_users_status_index")
    drop_if_exists index(:users, [:role], name: "tenant_users_role_index")
    drop_if_exists unique_index(:users, [:email], name: "tenant_users_unique_email_index")
    drop table(:users)
  end
end