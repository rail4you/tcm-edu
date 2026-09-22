defmodule TcmEdu.SimulatedPatient.Session do
  @moduledoc """
  学生与标准化病人之间的一次对话会话（租户域）。

  一次会话记录一段完整的问诊过程：

    * `assignment_id` — 触发的教师分配记录（可空，允许学生直接练习）
    * `patient_id`    — 病人档案（冗余存储，避免病人档案被改后历史失真）
    * `student_id`    — 学生
    * `patient_snapshot` — 创建时从 patient 拷贝的病人档案（姓名、主诉、性格、评分要点等），
      用于对话 prompt 与 AI 评分，确保历史会话数据稳定
    * `status`        — `:active` / `:completed` / `:abandoned`
    * `turn_count`    — 学生发送的消息数
    * `ended_at`      — 学生主动结束 / 超时结束的时间
    * `evaluation_id` — 关联的最终评分记录

  多租户：`multitenancy :context`。
  """

  use Ash.Resource,
    domain: TcmEdu.SimulatedPatient,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("simulated_patient_sessions")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :patient_snapshot, :map do
      allow_nil?(false)
      public?(true)
      description("创建时从 Patient 拷贝的快照（人设、主诉、性格、评分要点）")
    end

    attribute :status, :atom do
      default(:active)
      constraints(one_of: [:active, :completed, :abandoned])
      public?(true)
    end

    attribute :turn_count, :integer do
      default(0)
      public?(true)
      description("学生已发送消息数（每次学生发言后 +1）")
    end

    attribute :ended_at, :utc_datetime do
      public?(true)
    end

    attribute :ended_reason, :string do
      public?(true)
      description("结束原因：student_finished / timeout / max_turns")
    end

    attribute :evaluation_status, :atom do
      default(:none)
      constraints(one_of: [:none, :pending, :running, :completed, :failed])
      public?(true)
    end

    attribute :evaluation_error, :string do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :assignment, TcmEdu.SimulatedPatient.Assignment do
      public?(true)
    end

    belongs_to :patient, TcmEdu.SimulatedPatient.Patient do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :student, TcmEdu.Accounts.User do
      allow_nil?(false)
      public?(true)
    end

    has_many :messages, TcmEdu.SimulatedPatient.Message do
      destination_attribute(:session_id)
      public?(true)
    end

    has_one :evaluation, TcmEdu.SimulatedPatient.Evaluation do
      destination_attribute(:session_id)
      public?(true)
    end
  end

  aggregates do
    count(:message_count, :messages)
  end

  code_interface do
    define(:list_sessions, action: :read)
    define(:get_session, action: :read, get_by: [:id])
    define(:create_session, action: :create)
    define(:delete_session, action: :destroy)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :assignment_id,
        :patient_id,
        :student_id,
        :patient_snapshot,
        :status,
        :evaluation_status
      ])

      validate(present([:patient_snapshot, :patient_id, :student_id]))
    end

    update :update do
      primary?(true)
      accept([:status, :turn_count, :ended_at, :ended_reason, :evaluation_status])
    end

    update :increment_turn do
      require_atomic?(false)
      accept([])

      change(fn changeset, _ctx ->
        current = Ash.Changeset.get_attribute(changeset, :turn_count) || 0
        Ash.Changeset.change_attribute(changeset, :turn_count, current + 1)
      end)
    end

    update :mark_ended do
      require_atomic?(false)

      accept([:status, :ended_reason])

      change(set_attribute(:ended_at, &DateTime.utc_now/0))
    end

    update :set_evaluation_status do
      require_atomic?(false)
      accept([:evaluation_status, :evaluation_error])
    end

    read :for_student do
      argument(:student_id, :uuid, allow_nil?: false)
      filter(expr(student_id == ^arg(:student_id)))
      prepare(build(sort: [inserted_at: :desc]))
    end

    read :for_patient do
      argument(:patient_id, :uuid, allow_nil?: false)
      filter(expr(patient_id == ^arg(:patient_id)))
      prepare(build(sort: [inserted_at: :desc]))
    end

    read :mine_active do
      argument(:student_id, :uuid, allow_nil?: false)
      filter(expr(student_id == ^arg(:student_id) and status == :active))
      prepare(build(sort: [inserted_at: :desc]))
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(expr(student_id == ^actor(:id)))
    end

    policy action_type(:create) do
      authorize_if(expr(student_id == ^actor(:id)))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action_type([:update, :destroy]) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(expr(student_id == ^actor(:id)))
    end
  end
end
