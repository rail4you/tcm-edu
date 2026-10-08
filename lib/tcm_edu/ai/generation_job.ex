defmodule TcmEdu.AI.GenerationJob do
  @moduledoc """
  AI 生成任务（租户域）：`kind = :lesson_plan | :image`。

  教师在 AI 备课 / AI 配图页提交需求后，本资源记录一行业务状态，
  真正的耗时工作由 `TcmEdu.Workers.AiGenerationWorker`（Oban）在后台完成：

    * `pending`   — 已提交，等待 Oban 执行
    * `running`   — Worker 已开始，正在调用模型
    * `completed` — 生成成功，结果存于 `result`
    * `failed`    — 生成失败，原因见 `error_message`

  Worker 每次状态变迁向 `ai_jobs:<tenant>` 广播
  `{:ai_job_event, type, payload}`，并写一条站内通知。因为执行与 LiveView
  进程无关，教师中途离开页面不会中断生成；结果落库后，再次进入页面
  即可看到进度或结果。
  """

  use Ash.Resource,
    domain: TcmEdu.AIJobs,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("ai_generation_jobs")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :kind, :atom do
      allow_nil?(false)
      constraints(one_of: [:lesson_plan, :image])
      public?(true)
      description("任务类型：备课 / 配图")
    end

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
      description("任务标题（备课主题 / 画面描述摘要）")
    end

    attribute :params, :map do
      default(%{})
      public?(true)
      description("提交时的原始参数")
    end

    attribute :result, :map do
      public?(true)
      description("生成结果（备课：{\"plan\" => md}；配图：{\"urls\" => [...]}）")
    end

    attribute :status, :atom do
      default(:pending)
      constraints(one_of: [:pending, :running, :completed, :failed])
      public?(true)
    end

    attribute :progress, :integer do
      default(0)
      constraints(min: 0, max: 100)
      public?(true)
      description("完成进度百分比（0-100）")
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
    belongs_to :requested_by, TcmEdu.Accounts.User do
      source_attribute(:requested_by_id)
      destination_attribute(:id)
      define_attribute?(false)
      public?(true)
    end
  end

  code_interface do
    define(:list_generation_jobs, action: :read)
    define(:get_generation_job, action: :read, get_by: [:id])
    define(:request_generation_job, action: :request)
  end

  actions do
    defaults([:read, :destroy])

    create :request do
      primary?(true)
      description("提交一次 AI 生成任务")

      accept([
        :kind,
        :title,
        :params,
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
      change(set_attribute(:progress, 10))
      change(set_attribute(:started_at, &DateTime.utc_now/0))
    end

    update :mark_completed do
      require_atomic?(false)
      accept([:result])
      change(set_attribute(:status, :completed))
      change(set_attribute(:progress, 100))
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
      change(set_attribute(:progress, 0))
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

    read :latest_mine do
      description("我最近的一条指定类型任务（用于进入页面时恢复进度/结果）")
      argument(:requested_by_id, :uuid, allow_nil?: false)
      argument(:kind, :atom, allow_nil?: false)
      filter(expr(requested_by_id == ^arg(:requested_by_id) and kind == ^arg(:kind)))
      prepare(build(sort: [inserted_at: :desc], limit: 1))
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
