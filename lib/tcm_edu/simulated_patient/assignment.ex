defmodule TcmEdu.SimulatedPatient.Assignment do
  @moduledoc """
  教师把标准化病人分配给学生的记录（租户域）。

  一次分配对应一次练习任务：

    * `patient_id` — 标准化病人档案
    * `student_id` — 学生用户
    * `assigned_by_id` — 发起分配的教师
    * `deadline`   — 截止时间（可选）
    * `status`     — `:assigned` / `:in_progress` / `:completed` / `:expired`
    * `notes`      — 教师给学生的附加说明

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
    table("simulated_patient_assignments")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :deadline, :utc_datetime do
      public?(true)
    end

    attribute :status, :atom do
      default(:assigned)
      constraints(one_of: [:assigned, :in_progress, :completed, :expired])
      public?(true)
    end

    attribute :notes, :string do
      public?(true)
    end

    attribute :assigned_by_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :assigned_by_email, :string do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :patient, TcmEdu.SimulatedPatient.Patient do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :student, TcmEdu.Accounts.User do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :assigned_by, TcmEdu.Accounts.User do
      source_attribute(:assigned_by_id)
      destination_attribute(:id)
      define_attribute?(false)
      public?(true)
    end
  end

  calculations do
    calculate :is_overdue,
              :boolean,
              expr(
                not is_nil(deadline) and deadline < now() and status in [:assigned, :in_progress]
              ) do
      public?(true)
    end
  end

  code_interface do
    define(:list_assignments, action: :read)
    define(:get_assignment, action: :read, get_by: [:id])
    define(:create_assignment, action: :create)
    define(:delete_assignment, action: :destroy)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      description("教师把病人分配给学生")

      accept([
        :patient_id,
        :student_id,
        :deadline,
        :notes,
        :assigned_by_id,
        :assigned_by_email,
        :status
      ])

      validate(string_length(:notes, max: 1000))
    end

    update :update do
      primary?(true)
      accept([:deadline, :notes, :status])
    end

    update :mark_in_progress do
      require_atomic?(false)
      accept([])
      change(set_attribute(:status, :in_progress))
    end

    update :mark_completed do
      require_atomic?(false)
      accept([])
      change(set_attribute(:status, :completed))
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

    read :mine_created do
      argument(:assigned_by_id, :uuid, allow_nil?: false)
      filter(expr(assigned_by_id == ^arg(:assigned_by_id)))
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

    # 教师可读所有（自己租户的）；学生只能读自己被分配的。
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(expr(student_id == ^actor(:id)))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    # 学生可以把 assigned → in_progress / completed
    policy action([:mark_in_progress, :mark_completed]) do
      authorize_if(expr(student_id == ^actor(:id)))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end
  end
end
