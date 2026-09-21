defmodule TcmEdu.Quiz.QuizJob do
  @moduledoc """
  AI 习题生成任务（租户域）。

  教师在 `/teacher/ai/quiz` 提交生成需求后，本资源记录一行业务状态，
  真正的耗时工作由 `TcmEdu.Workers.QuizGenerationWorker`（Oban）在后台完成：

    * `pending`   — 已提交，等待 Oban 执行
    * `running`   — Worker 已开始，正在调 Jido agent 生成
    * `completed` — 生成成功，题目已写入目标题库（`question_ids`）
    * `failed`    — 生成失败，原因见 `error_message`

  Worker 在每次状态变迁时向 `quiz_jobs:<tenant>` PubSub topic 广播
  `{:quiz_job_event, type, payload}`，LiveView 订阅后刷新列表并展示
  banner。因为执行与 LiveView 进程无关，教师中途离开页面也不会中断生成。
  """

  use Ash.Resource,
    domain: TcmEdu.Quiz,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("quiz_jobs")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :topic, :string do
      allow_nil?(false)
      public?(true)
      description("出题主题，如：手太阴肺经腧穴")
    end

    attribute :subject, :string do
      default("中医")
      public?(true)
      description("学科，如：中医基础 / 解剖学")
    end

    attribute :question_count, :integer do
      default(5)
      constraints(min: 1, max: 20)
      public?(true)
      description("期望生成的题目数量")
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
      description("知识点（逗号分隔输入，存数组）")
    end

    attribute :requirements, :string do
      public?(true)
      description("补充要求（可选），直接拼进 prompt")
    end

    attribute :status, :atom do
      default(:pending)
      constraints(one_of: [:pending, :running, :completed, :failed])
      public?(true)
    end

    attribute :generated_count, :integer do
      default(0)
      public?(true)
      description("实际成功写入题库的题目数")
    end

    attribute :question_ids, {:array, :string} do
      default([])
      public?(true)
      description("已生成的题目 id 列表")
    end

    attribute :error_message, :string do
      public?(true)
    end

    attribute :oban_job_id, :integer do
      public?(true)
      description("关联的 Oban job id（测试 manual 模式下可能为 nil）")
    end

    attribute :requested_by_id, :uuid do
      allow_nil?(false)
      public?(true)
      description("发起人（User id，用于 PubSub 过滤与 banner 归属）")
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
      description("生成的题目写入的目标题库")
    end

    belongs_to :requested_by, TcmEdu.Accounts.User do
      source_attribute(:requested_by_id)
      destination_attribute(:id)
      define_attribute?(false)
      public?(true)
    end
  end

  code_interface do
    define(:list_quiz_jobs, action: :read)
    define(:get_quiz_job, action: :read, get_by: [:id])
    define(:request_quiz_job, action: :request)
  end

  actions do
    defaults([:read, :destroy])

    create :request do
      primary?(true)
      description("提交一次 AI 出题任务")

      accept([
        :topic,
        :subject,
        :question_count,
        :question_types,
        :difficulty,
        :knowledge_points,
        :requirements,
        :bank_id,
        :requested_by_id,
        :requested_by_email
      ])
    end

    update :set_oban_job do
      description("记录 Oban job id")
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
      accept([:generated_count, :question_ids])
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
      description("失败任务重试：回到 pending，清空错误信息")
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

    policy action_type(:create) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action_type(:update) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action_type(:destroy) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end
  end
end
