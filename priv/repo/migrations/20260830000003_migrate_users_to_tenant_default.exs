defmodule TcmEdu.Repo.Migrations.MigrateUsersToTenantDefault do
  @moduledoc """
  Phase 3 数据迁移：把 `public.users` + 旧 RBAC 表全部归档到 `tenant_default`。

  背景：
    * 旧 User 资源无 multitenancy，所有数据存 `public.users`
    * 旧 RBAC 系统（roles/permissions/user_roles/...）废弃
    * 改为：User multitenancy :context，所有数据存 `tenant_<slug>.users`

  步骤：
    1. 复制 public.users → tenant_default.users（role: admin→tenant_admin，user→student）
    2. 删除 public.users + RBAC 表
    3. 旧 super_admin 登录流程不受影响（独立 public.super_admins 表）
  """

  use Ecto.Migration

  def up do
    # 仅删除旧 RBAC 表；public.users 的数据和 schema 本身由
    # `mix tcm_edu.migrate` 任务在主迁移 + 租户迁移后统一处理。
    # 注意：users1 被一些演示表（learned_files/learned_questions）引用，
    # 需 CASCADE 连带删除。
    execute("DROP TABLE IF EXISTS public.users1 CASCADE")

    drop_if_exists table(:users_tokens)
    drop_if_exists table(:user_roles)
    drop_if_exists table(:user_permissions)
    drop_if_exists table(:role_permissions)
    drop_if_exists table(:roles)
    drop_if_exists table(:permissions)
  end

  def down do
    # 重建 public.users（仅用于本地回滚演练）
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

    create unique_index(:users, [:email], name: "users_unique_email_index")

    execute """
    INSERT INTO public.users (id, email, hashed_password, role, inserted_at, updated_at, status)
    SELECT id,
           email,
           hashed_password,
           CASE role
             WHEN 'tenant_admin' THEN 'admin'
             ELSE 'user'
           END,
           inserted_at,
           updated_at,
           'active'
    FROM tenant_default.users
    ON CONFLICT (id) DO NOTHING
    """
  end
end
