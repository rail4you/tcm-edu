defmodule TcmEdu.Repo.TenantMigrations.CreateTenantEnrollments do
  @moduledoc """
  租户域选课表迁移。每个 `tenant_*` schema 都会跑一次。

  建 2 张表：`enrollments` / `progress`。
  外键均在同一 schema 内（migration 带 prefix 执行）。

  唯一索引名必须对齐 Ash 约定（`<table>_<identity>_index`），
  否则唯一冲突时报 500 而非 422（见 00004 改名迁移）。
  """

  use Ecto.Migration

  def up do
    create table(:enrollments, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :status, :string, null: false, default: "active"
      add :enrolled_at, :utc_datetime, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :expires_at, :utc_datetime, null: true
      add :completed_at, :utc_datetime, null: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :course_id, references(:courses, type: :uuid, on_delete: :delete_all), null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:enrollments, [:user_id, :course_id], name: "enrollments_unique_user_course_index")
    create index(:enrollments, [:user_id], name: "tenant_enrollments_user_index")
    create index(:enrollments, [:course_id], name: "tenant_enrollments_course_index")

    create table(:progress, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :status, :string, null: false, default: "not_started"
      add :progress_pct, :integer, null: false, default: 0
      add :last_position_seconds, :integer, null: false, default: 0
      add :completed_at, :utc_datetime, null: true
      add :enrollment_id, references(:enrollments, type: :uuid, on_delete: :delete_all), null: false
      add :lesson_id, references(:lessons, type: :uuid, on_delete: :delete_all), null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:progress, [:enrollment_id, :lesson_id],
             name: "progress_unique_enrollment_lesson_index"
           )

    create index(:progress, [:enrollment_id], name: "tenant_progress_enrollment_index")
    create index(:progress, [:lesson_id], name: "tenant_progress_lesson_index")
  end

  def down do
    drop_if_exists table(:progress)
    drop_if_exists table(:enrollments)
  end
end
