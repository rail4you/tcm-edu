defmodule TcmEdu.Repo.TenantMigrations.CreateTenantCourses do
  @moduledoc """
  租户域课程表迁移。每个 `tenant_*` schema 都会跑一次。

  建 4 张表：`course_categories` / `courses` / `chapters` / `lessons`。
  外键均在同一 schema 内（migration 带 prefix 执行）。
  """

  use Ecto.Migration

  def up do
    create table(:course_categories, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :icon, :string, null: true
      add :sort_order, :integer, null: false, default: 0
      add :parent_id, references(:course_categories, type: :uuid, on_delete: :nilify_all), null: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:course_categories, [:slug], name: "tenant_course_categories_slug_index")

    create table(:courses, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :title, :string, null: false
      add :subtitle, :string, null: true
      add :description, :text, null: true
      add :cover_image_url, :string, null: true
      add :tags, {:array, :string}, null: false, default: []
      add :level, :string, null: false, default: "beginner"
      add :status, :string, null: false, default: "draft"
      add :price_cents, :integer, null: false, default: 0
      add :published_at, :utc_datetime, null: true
      add :teacher_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :category_id, references(:course_categories, type: :uuid, on_delete: :nilify_all), null: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:courses, [:teacher_id], name: "tenant_courses_teacher_index")
    create index(:courses, [:category_id], name: "tenant_courses_category_index")
    create index(:courses, [:status], name: "tenant_courses_status_index")

    create table(:chapters, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :title, :string, null: false
      add :sort_order, :integer, null: false, default: 0
      add :course_id, references(:courses, type: :uuid, on_delete: :delete_all), null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:chapters, [:course_id], name: "tenant_chapters_course_index")

    create table(:lessons, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :title, :string, null: false
      add :content_type, :string, null: false, default: "video"
      add :content_url, :string, null: true
      add :content_text, :text, null: true
      add :duration_seconds, :integer, null: false, default: 0
      add :sort_order, :integer, null: false, default: 0
      add :is_free_preview, :boolean, null: false, default: false
      add :chapter_id, references(:chapters, type: :uuid, on_delete: :delete_all), null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:lessons, [:chapter_id], name: "tenant_lessons_chapter_index")
  end

  def down do
    drop_if_exists table(:lessons)
    drop_if_exists table(:chapters)
    drop_if_exists table(:courses)
    drop_if_exists table(:course_categories)
  end
end
