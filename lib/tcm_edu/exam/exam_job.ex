defmodule TcmEdu.Exam.ExamJob do
  @moduledoc """
  AI 智能组卷任务（租户域）。

  教师在 `/teacher/exams` 提交 AI 组卷需求后，本资源记录一行业务状态，
  真正的工作由 `TcmEdu.Workers.ExamGenerationWorker`（Oban）在后台完成：

    * `pending`   — 已提交，等待 Oban 执行
    * `running`   — Worker 已开始，正在从题库选材组卷
    * `completed` — 组卷成功，已生成试卷（`exam_id`）
    * `failed`    — 组卷失败，原因见 `error_message`

  Worker 在状态变迁时向 `exam_jobs:<tenant>` PubSub topic 广播
  `{:exam_job_event, type, payload}`，教师端页面订阅后刷新列表并展示 banner。
  """

  use Ash.Resource,
    domain: TcmEdu.Exam,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("exam_jobs")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
      description("将生成的试卷名称")
    end

    attribute :description, :string do
      public?(true)
    end

    attribute :topic, :string do
      public?(true)
      description("组卷主题/侧重，如：手太阴肺经腧穴")
    end

    attribute :subject, :string do
      default("中医")
      public?(true)
      description("学科，如：中医基础 / 解剖学")
    end

    attribute :question_count, :integer do
      default(5)
      constraints(min: 1, max: 30)
      public?(true)
      description("期望试卷题目数量")
    end

    attribute :question_types, {:array, :string} do
      default(["single"])
      public?(true)
      description("题型组合：single / multi / judge / essay")
    end

    attribute :difficulty, :integer do
      default(3)
      constraints(min: 1, max: 5)
      public?(true)
    end

    attribute :knowledge_points, {:array, :string} do
      default([])
      public?(true)
    end

    attribute :total_score, :integer do
      default(100)
      constraints(min: 10, max: 500)
      public?(true)
      description("试卷总分（按题均分）")
    end

    attribute :status, :atom do
      default(:pending)
      constraints(one_of: [:pending, :running, :completed, :failed])
      public?(true)
    end

    attribute :error_message, :string do
      public?(true)
    end

    attribute :oban_job_id, :integer do
      public?(true)
    end

    attribute :requested_by_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :requested_by_email, :string do
      public?(true)
    end

    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)

    attribute :started_at, :utc_datetime do
      public?(true)
    end

    attribute :completed_at, :utc_datetime do
      public?(true)
    end
  end

  relationships do
    belongs_to :bank, TcmEdu.Quiz.QuestionBank do
      allow_nil?(false)
      public?(true)
      description("从中选题的题库")
    end

    belongs_to :exam, TcmEdu.Exam.Exam do
      allow_nil?(true)
      public?(true)
      description("组卷成功生成的试卷")
    end

    belongs_to :requested_by, TcmEdu.Accounts.User do
      source_attribute(:requested_by_id)
      destination_attribute(:id)
      define_attribute?(false)
      public?(true)
    end
  end

  code_interface do
    define(:list_exam_jobs, action: :read)
    define(:get_exam_job, action: :read, get_by: [:id])
    define(:request_exam_job, action: :request)
  end

  actions do
    defaults([:read, :destroy])

    create :request do
      primary?(true)
      description("提交一次 AI 组卷任务")

      accept([
        :name,
        :description,
        :topic,
        :subject,
        :question_count,
        :question_types,
        :difficulty,
        :knowledge_points,
        :total_score,
        :bank_id,
        :requested_by_id,
        :requested_by_email
      ])
    end

    update :set_oban_job do
      require_atomic?(false)
      accept([:oban_job_id])
    end

    update :mark_running do
      require_atomic?(false)
      accept([])
      change(set_attribute(:status, :running))
      change(set_attribute(:started_at, &DateTime.utc_now/0))
    end

    update :mark_completed do
      require_atomic?(false)
      accept([:exam_id])
      change(set_attribute(:status, :completed))
      change(set_attribute(:completed_at, &DateTime.utc_now/0))
    end

    update :mark_failed do
      require_atomic?(false)
      accept([:error_message])
      change(set_attribute(:status, :failed))
      change(set_attribute(:completed_at, &DateTime.utc_now/0))
    end

    update :retry do
      description("失败任务重试：回到 pending")
      require_atomic?(false)
      accept([:oban_job_id])
      change(set_attribute(:status, :pending))
      change(set_attribute(:error_message, nil))
      change(set_attribute(:started_at, nil))
      change(set_attribute(:completed_at, nil))
    end

    read :list_mine do
      description("我发起的任务（按时间倒序）")
      argument(:requested_by_id, :uuid, allow_nil?: false)
      filter(expr(requested_by_id == ^arg(:requested_by_id)))
      prepare(build(sort: [inserted_at: :desc]))
    end

    read :recent_completed do
      description("我最近完成的任务（用于进入页面时的 banner）")
      argument(:requested_by_id, :uuid, allow_nil?: false)
      filter(expr(requested_by_id == ^arg(:requested_by_id) and status == :completed))
      prepare(build(sort: [completed_at: :desc]))
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
      authorize_if(always())
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end
  end
end
