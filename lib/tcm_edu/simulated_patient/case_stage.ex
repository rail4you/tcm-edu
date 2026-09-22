defmodule TcmEdu.SimulatedPatient.CaseStage do
  @moduledoc """
  全流程临床模拟的阶段进度（租户域，session 1:N）。

  把一次会话拆成七个临床思维阶段，逐阶段推进：

    * `:inquiry`        — 问诊（已有）
    * `:physical_exam`  — 体格检查
    * `:auxiliary`      — 辅助检查
    * `:diagnosis`      — 诊断
    * `:differential`   — 鉴别诊断
    * `:treatment`      — 治疗方案
    * `:follow_up`      — 随访

  每个阶段记录学员在该阶段的动作（`student_actions`，JSON 数组，内容由
  `AI.ClinicalReasoning` 结构化产生），以及是否通过实时对比标准路径标记了
  思维漏洞（`reasoning_gaps`）。`status` 控制推进：`locked`（未解锁）/
  `available`（当前可操作）/ `completed` / `skipped`。

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
    table("simulated_patient_case_stages")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :stage, :atom do
      allow_nil?(false)
      constraints(
        one_of: [
          :inquiry,
          :physical_exam,
          :auxiliary,
          :diagnosis,
          :differential,
          :treatment,
          :follow_up
        ]
      )

      public?(true)
      description("临床思维阶段")
    end

    attribute :order, :integer do
      allow_nil?(false)
      constraints(min: 1, max: 7)
      public?(true)
      description("阶段顺序（问诊=1 … 随访=7）")
    end

    attribute :status, :atom do
      default(:locked)
      constraints(one_of: [:locked, :available, :completed, :skipped])
      public?(true)
      description("阶段状态：未解锁 / 当前可操作 / 已完成 / 已跳过")
    end

    attribute :student_actions, {:array, :map} do
      default([])
      public?(true)
      description("学员在本阶段的动作记录（结构化 JSON，供标准路径对比与评分）")
    end

    attribute :reasoning_gaps, {:array, :map} do
      default([])
      public?(true)
      description("实时对比标准路径标记出的思维漏洞（见 StandardPathwayComparator）")
    end

    attribute :completed_at, :utc_datetime do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :session, TcmEdu.SimulatedPatient.Session do
      allow_nil?(false)
      public?(true)
    end
  end

  code_interface do
    define(:list_case_stages, action: :read)
    define(:get_case_stage, action: :read, get_by: [:id])
    define(:create_case_stage, action: :create)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:session_id, :stage, :order, :status, :student_actions, :reasoning_gaps])
      validate(present([:session_id, :stage, :order]))
    end

    update :update do
      primary?(true)
      accept([:status, :student_actions, :reasoning_gaps, :completed_at])
    end

    update :activate do
      description("把阶段置为可操作（解锁）")
      require_atomic?(false)
      accept([])
      change(set_attribute(:status, :available))
    end

    update :complete do
      description("标记阶段完成并记录完成时间")
      require_atomic?(false)
      accept([:student_actions, :reasoning_gaps])
      change(set_attribute(:status, :completed))
      change(set_attribute(:completed_at, &DateTime.utc_now/0))
    end

    update :skip do
      description("跳过阶段（非急诊简化流程允许）")
      require_atomic?(false)
      accept([])
      change(set_attribute(:status, :skipped))
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if(always())
    end

    # 学生可读写自己会话的阶段；教师/租户管理员只读。
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(expr(exists(session, student_id == ^actor(:id))))
    end

    policy action_type([:create, :update]) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(expr(exists(session, student_id == ^actor(:id))))
    end

    policy action_type(:destroy) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end
  end
end