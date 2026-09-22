defmodule TcmEdu.SimulatedPatient.ClinicalReasoningReport do
  @moduledoc """
  临床思维能力报告（租户域）。

  由 `TcmEdu.Workers.ClinicalReasoningReportWorker` 异步汇总某学生在某周期内的
  多次临床模拟会话，产出六维能力打分与短板分析。维度：

    * `inquiry_score`       — 问诊完整度
    * `physical_exam_score` — 查体规范度
    * `auxiliary_score`     — 检查合理性
    * `diagnosis_score`     — 诊断准确性
    * `differential_score`  — 鉴别诊断全面性
    * `treatment_score`     — 治疗合理性
    * `follow_up_score`     — 随访与复诊把握

  报告还包含与同期同学对比的排名（`rank` / `peer_count`）与统计信息
  （`statistics` JSON），以及面向短板的个性化提升计划（`improvement_plan`）。

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
    table("clinical_reasoning_reports")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :student_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :report_period_start, :date do
      public?(true)
      description("报告统计周期起始日")
    end

    attribute :report_period_end, :date do
      public?(true)
      description("报告统计周期结束日")
    end

    attribute :inquiry_score, :integer do
      default(0)
      constraints(min: 0, max: 100)
      public?(true)
    end

    attribute :physical_exam_score, :integer do
      default(0)
      constraints(min: 0, max: 100)
      public?(true)
    end

    attribute :auxiliary_score, :integer do
      default(0)
      constraints(min: 0, max: 100)
      public?(true)
    end

    attribute :diagnosis_score, :integer do
      default(0)
      constraints(min: 0, max: 100)
      public?(true)
      description("诊断准确性")
    end

    attribute :differential_score, :integer do
      default(0)
      constraints(min: 0, max: 100)
      public?(true)
      description("鉴别诊断全面性")
    end

    attribute :treatment_score, :integer do
      default(0)
      constraints(min: 0, max: 100)
      public?(true)
      description("治疗合理性")
    end

    attribute :follow_up_score, :integer do
      default(0)
      constraints(min: 0, max: 100)
      public?(true)
    end

    attribute :total_score, :decimal do
      public?(true)
      description("六维加权总分")
    end

    attribute :grade, :atom do
      constraints(one_of: [:excellent, :good, :pass, :borderline, :fail])
      public?(true)
    end

    attribute :rank, :integer do
      public?(true)
      description("本周期内同学中排名（1 = 最高）")
    end

    attribute :peer_count, :integer do
      public?(true)
      description("本周期参与对比的同学人数")
    end

    attribute :statistics, :map do
      default(%{})
      public?(true)
      description("统计信息 JSON（各维度百分位 / 均值等）")
    end

    attribute :dimension_report, :map do
      default(%{})
      public?(true)
      description("各维度详细报告 JSON（每维：短板 / 建议 / 覆盖样例）")
    end

    attribute :improvement_plan, :string do
      public?(true)
      description("面向短板的个性化提升计划（markdown）")
    end

    attribute :session_count, :integer do
      default(0)
      public?(true)
      description("纳入统计的会话数")
    end

    attribute :generated_at, :utc_datetime do
      default(&DateTime.utc_now/0)
      public?(true)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :student, TcmEdu.Accounts.User do
      source_attribute(:student_id)
      destination_attribute(:id)
      define_attribute?(false)
      public?(true)
    end
  end

  code_interface do
    define(:list_reports, action: :read)
    define(:get_report, action: :read, get_by: [:id])
    define(:create_report, action: :create)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)

      accept([
        :student_id,
        :report_period_start,
        :report_period_end,
        :inquiry_score,
        :physical_exam_score,
        :auxiliary_score,
        :diagnosis_score,
        :differential_score,
        :treatment_score,
        :follow_up_score,
        :total_score,
        :grade,
        :rank,
        :peer_count,
        :statistics,
        :dimension_report,
        :improvement_plan,
        :session_count,
        :generated_at
      ])

      validate(present([:student_id]))
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