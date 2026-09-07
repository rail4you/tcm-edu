defmodule TcmEdu.Enrollment.Progress do
  @moduledoc """
  学习进度（租户域）：`enrollment × lesson` 粒度，前端心跳上报。

  * `upsert_progress`：按 `unique_enrollment_lesson` upsert，心跳直接调它即可
  * `progress_pct >= 100` 自动落 `status = :completed` + `completed_at`
  * 读写限本人（`enrollment.user_id == actor.id`）或管理员；
    教师可读自己课程的进度（批改/学情视角）

  多租户：`multitenancy :context`，调用必须带 `tenant: "tenant_<slug>"`。
  """

  use Ash.Resource,
    domain: TcmEdu.Enrollment,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource],
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table "progress"
    repo TcmEdu.Repo
  end

  typescript do
    type_name "Progress"
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      default :not_started
      constraints one_of: [:not_started, :in_progress, :completed]
      public? true
    end

    attribute :progress_pct, :integer do
      default 0
      constraints min: 0, max: 100
      public? true
    end

    attribute :last_position_seconds, :integer do
      default 0
      public? true
    end

    attribute :completed_at, :utc_datetime do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :enrollment, TcmEdu.Enrollment.Enrollment do
      allow_nil? false
      public? true
    end

    belongs_to :lesson, TcmEdu.Courses.Lesson do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_enrollment_lesson, [:enrollment_id, :lesson_id]
  end

  code_interface do
    define :upsert_progress, action: :upsert_progress
    define :update_progress, action: :update
  end

  actions do
    defaults [:read]

    create :upsert_progress do
      description "心跳上报：存在则更新，不存在则创建"
      upsert? true
      upsert_identity :unique_enrollment_lesson
      upsert_fields [:status, :progress_pct, :last_position_seconds]

      accept [
        :enrollment_id,
        :lesson_id,
        :status,
        :progress_pct,
        :last_position_seconds
      ]

      change {TcmEdu.Enrollment.Changes.AutoComplete, []}
    end

    update :update do
      description "更新进度（前端心跳调用）"
      require_atomic? false

      accept [:status, :progress_pct, :last_position_seconds]

      change {TcmEdu.Enrollment.Changes.AutoComplete, []}
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if always()
    end

    # 读：管理员；教师看自己课程的；学生看自己的
    policy action(:read) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
      authorize_if expr(enrollment.course.teacher_id == ^actor(:id))
      authorize_if expr(enrollment.user_id == ^actor(:id))
    end

    # 写：管理员，或该 enrollment 的属主学生
    policy action(:upsert_progress) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
      authorize_if relates_to_actor_via([:enrollment, :user])
    end

    policy action(:update) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
      authorize_if relates_to_actor_via([:enrollment, :user])
    end
  end
end
