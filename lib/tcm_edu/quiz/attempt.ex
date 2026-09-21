defmodule TcmEdu.Quiz.Attempt do
  @moduledoc """
  学员作答记录（租户域）：`user × question` 的一次作答。

  * `source`   — 来源：`practice`（刷题）/ `exam`（考试）/ `homework`（作业）
  * `is_correct` — 客观题自动判分结果；主观题为 nil
  * `ai_explanation` — AI 错题解析缓存（避免重复调用模型）

  错题本 = `is_correct == false` 的 Attempt 集合。

  多租户：`multitenancy :context`。
  """

  use Ash.Resource,
    domain: TcmEdu.Quiz,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  multitenancy do
    strategy :context
  end

  postgres do
    table("question_attempts")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :answer, :string do
      public?(true)
      description("学员提交的答案")
    end

    attribute :is_correct, :boolean do
      public?(true)
    end

    attribute :score, :decimal do
      public?(true)
    end

    attribute :source, :atom do
      default(:practice)
      constraints(one_of: [:practice, :exam, :homework])
      public?(true)
    end

    attribute :duration_seconds, :integer do
      default(0)
      public?(true)
    end

    attribute :ai_explanation, :string do
      public?(true)
      description("AI 错题解析缓存（markdown）")
    end

    attribute :ai_explained_at, :utc_datetime do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :user, TcmEdu.Accounts.User do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :question, TcmEdu.Quiz.Question do
      allow_nil?(false)
      public?(true)
    end
  end

  code_interface do
    define(:list_attempts, action: :read)
    define(:get_attempt, action: :read, get_by: [:id])
    define(:submit_attempt, action: :submit)
    define(:my_attempts, action: :my_attempts)
    define(:my_mistakes, action: :my_mistakes)
  end

  actions do
    defaults([:read])

    create :submit do
      primary?(true)
      description("学员提交作答；用户强制取 actor，判分由 Quiz.Grading 完成")

      accept([:question_id, :answer, :score, :source, :duration_seconds])

      change(relate_actor(:user))

      change(
        after_action(fn _changeset, attempt, _context ->
          # 判分：交给 Grading 模块（纯函数，见 TcmEdu.Quiz.Grading）
          TcmEdu.Quiz.Grading.grade_and_persist(attempt)
        end)
      )
    end

    read :my_attempts do
      description("当前登录学员的全部作答记录")
      filter(expr(user_id == ^actor(:id)))
    end

    read :my_mistakes do
      description("当前登录学员的错题（is_correct == false）")
      filter(expr(user_id == ^actor(:id) and is_correct == false))
    end

    update :grade do
      primary?(true)
      description("由 Grading 写判分结果（is_correct + score）")
      accept([:is_correct, :score])
    end

    update :cache_ai_explanation do
      description("写入 AI 错题解析缓存")
      accept([:ai_explanation])
      change(set_attribute(:ai_explained_at, &DateTime.utc_now/0))
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
      authorize_if(expr(user_id == ^actor(:id)))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    policy action_type(:create) do
      authorize_if(actor_present())
    end

    policy action(:cache_ai_explanation) do
      authorize_if(expr(user_id == ^actor(:id)))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end
  end
end
