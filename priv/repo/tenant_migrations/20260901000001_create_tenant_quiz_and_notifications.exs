defmodule TcmEdu.Repo.TenantMigrations.CreateTenantQuizAndNotifications do
  @moduledoc """
  租户域题库 + 通知表迁移。每个 `tenant_*` schema 都会跑一次。

  建 4 张表：`question_banks` / `questions` / `question_attempts` / `notifications`。
  外键均在同一 schema 内（migration 带 prefix 执行）。

  唯一索引名对齐 Ash 约定（`<table>_<identity>_index`），避免唯一冲突当 500。
  """

  use Ecto.Migration

  def up do
    create table(:question_banks, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :string, null: false
      add :description, :string, null: true
      add :subject, :string, null: true
      add :is_public, :boolean, null: false, default: false
      add :visible_after_enrollment, :boolean, null: false, default: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create table(:questions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :type, :string, null: false, default: "single"
      add :difficulty, :integer, null: false, default: 3
      add :stem, :text, null: false
      add :options, :jsonb, null: false, default: "[]"
      add :answer, :text, null: true
      add :explanation, :text, null: true
      add :media_url, :string, null: true
      add :tags, {:array, :string}, null: false, default: []
      add :knowledge_points, {:array, :string}, null: false, default: []
      add :status, :string, null: false, default: "active"
      add :bank_id, references(:question_banks, type: :uuid, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, type: :uuid, on_delete: :restrict), null: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:questions, [:bank_id], name: "tenant_questions_bank_index")
    create index(:questions, [:status], name: "tenant_questions_status_index")

    create table(:question_attempts, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :answer, :text, null: true
      add :is_correct, :boolean, null: true
      add :score, :numeric, null: true
      add :source, :string, null: false, default: "practice"
      add :duration_seconds, :integer, null: false, default: 0
      add :ai_explanation, :text, null: true
      add :ai_explained_at, :utc_datetime, null: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :question_id, references(:questions, type: :uuid, on_delete: :delete_all), null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:question_attempts, [:user_id], name: "tenant_question_attempts_user_index")
    create index(:question_attempts, [:question_id], name: "tenant_question_attempts_question_index")

    create table(:notifications, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :actor_id, :uuid, null: true
      add :type, :string, null: false, default: "system"
      add :title, :string, null: false
      add :body, :text, null: true
      add :payload, :jsonb, null: false, default: "{}"
      add :read_at, :utc_datetime, null: true
      add :recipient_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:notifications, [:recipient_id], name: "tenant_notifications_recipient_index")
    create index(:notifications, [:read_at], name: "tenant_notifications_read_at_index")
  end

  def down do
    drop_if_exists table(:notifications)
    drop_if_exists table(:question_attempts)
    drop_if_exists table(:questions)
    drop_if_exists table(:question_banks)
  end
end