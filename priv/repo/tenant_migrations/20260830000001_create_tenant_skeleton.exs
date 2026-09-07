defmodule TcmEdu.Repo.TenantMigrations.CreateTenantSkeleton do
  @moduledoc """
  租户骨架迁移：所有 `tenant_*` schema 都会跑这一组迁移。

  当前仅建一张 `tenant_system_info` 表用于：
    1. 验证 schema 已建好（+ Ecto 自动写入 `schema_migrations`）
    2. 给后续 Phase 提供位置存放租户级元数据（创建时间、版本等）

  后续 Phase 添加：
    * Phase 3：`tenant_users`（多租户 User）
    * Phase 6：`tenant_courses` / `tenant_chapters` / `tenant_lessons` / ...
    * Phase 7：`tenant_enrollments` / `tenant_progress_records`

  命名约定：所有租户表加 `tenant_` 前缀，避免与 public schema 表混淆。
  """

  use Ecto.Migration

  def up do
    create table(:tenant_system_info, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :schema_version, :string, null: false, default: "v1"
      add :provisioned_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end
  end

  def down do
    drop table(:tenant_system_info)
  end
end