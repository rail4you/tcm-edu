defmodule TcmEdu.SimulatedPatient.Evaluation do
  @moduledoc """
  模拟诊疗会话的 AI 评分记录（租户域）。

  在学生结束对话后由 `TcmEdu.Workers.SimulatedPatientEvaluationWorker`
  异步生成。评分维度：

    * `professional_score`  — 专业度（0-100）
    * `empathy_score`       — 同理心（0-100）
    * `communication_score` — 沟通技巧（0-100）
    * `total_score`         — 加权总分（按 Patient.rubric 权重计算）
    * `highlights`          — 表现亮点（数组）
    * `weaknesses`          — 不足之处（数组）
    * `key_points_hit`      — key_points 中已覆盖的关键问诊点
    * `key_points_missed`   — 未覆盖的关键问诊点
    * `feedback`            — 综合评语（markdown）
    * `model`               — 评分所用模型

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
    table("simulated_patient_evaluations")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :professional_score, :integer do
      public?(true)
      constraints(min: 0, max: 100)
    end

    attribute :empathy_score, :integer do
      public?(true)
      constraints(min: 0, max: 100)
    end

    attribute :communication_score, :integer do
      public?(true)
      constraints(min: 0, max: 100)
    end

    attribute :total_score, :decimal do
      public?(true)
      description("加权总分（按 rubric 比例，保留两位小数）")
    end

    attribute :diagnosis_score, :integer do
      default(0)
      constraints(min: 0, max: 100)
      public?(true)
      description("诊断准确性（0-100）")
    end

    attribute :differential_score, :integer do
      default(0)
      constraints(min: 0, max: 100)
      public?(true)
      description("鉴别诊断全面性（0-100）")
    end

    attribute :treatment_score, :integer do
      default(0)
      constraints(min: 0, max: 100)
      public?(true)
      description("治疗合理性（0-100）")
    end

    attribute :stage_scores, :map do
      default(%{})
      public?(true)
      description("各阶段（问诊/查体/检查/诊断/鉴别/治疗/随访）打分快照 JSON")
    end

    attribute :reasoning_gaps, {:array, :map} do
      default([])
      public?(true)
      description("整会同诊后汇总的思维漏洞（诊断思路 / 鉴别 / 治疗合理性）")
    end

    attribute :standard_pathway_snapshot, :map do
      public?(true)
      description("评分时使用的标准路径快照（用于校验用）")
    end

    attribute :rubric_snapshot, :map do
      public?(true)
      description("评分时使用的 rubric 快照")
    end

    attribute :grade, :atom do
      public?(true)
      constraints(one_of: [:excellent, :good, :pass, :borderline, :fail])
      description("等级：优秀 90+ / 良好 80-89 / 及格 70-79 / 边缘 60-69 / 不及格 <60")
    end

    attribute :feedback, :string do
      public?(true)
      description("综合评语（markdown）")
    end

    attribute :highlights, {:array, :string} do
      default([])
      public?(true)
    end

    attribute :weaknesses, {:array, :string} do
      default([])
      public?(true)
    end

    attribute :key_points_hit, {:array, :string} do
      default([])
      public?(true)
    end

    attribute :key_points_missed, {:array, :string} do
      default([])
      public?(true)
    end

    attribute :transcript_tokens, :integer do
      public?(true)
      description("评分输入的对话字数（用于排查超长问题）")
    end

    attribute :model, :string do
      public?(true)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :session, TcmEdu.SimulatedPatient.Session do
      allow_nil?(false)
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
  end

  code_interface do
    define(:list_evaluations, action: :read)
    define(:get_evaluation, action: :read, get_by: [:id])
    define(:create_evaluation, action: :create)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)

      accept([
        :session_id,
        :patient_id,
        :student_id,
        :professional_score,
        :empathy_score,
        :communication_score,
        :diagnosis_score,
        :differential_score,
        :treatment_score,
        :stage_scores,
        :reasoning_gaps,
        :standard_pathway_snapshot,
        :total_score,
        :rubric_snapshot,
        :grade,
        :feedback,
        :highlights,
        :weaknesses,
        :key_points_hit,
        :key_points_missed,
        :transcript_tokens,
        :model
      ])
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
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end
  end
end
