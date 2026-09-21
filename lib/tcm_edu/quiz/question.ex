defmodule TcmEdu.Quiz.Question do
  @moduledoc """
  题目（租户域），归属题库。

  * `type`      — 题型：`single`（单选）/ `multi`（多选）/ `judge`（判断）/ `essay`（简答）
  * `options`   — 选项数组，形如 `[%{label: "A", text: "…", correct: true}]`
  * `answer`    — essay 题的参考答案 / judge 题的"对"/"错"
  * `stem`      — 题干
  * `difficulty`  1-5
  * `knowledge_points` — 关联知识点，供智能组卷 / 错题分析

  多租户：`multitenancy :context`。
  """

  use Ash.Resource,
    domain: TcmEdu.Quiz,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource],
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("questions")
    repo(TcmEdu.Repo)
  end

  typescript do
    type_name("Question")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :type, :atom do
      allow_nil?(false)
      default(:single)
      constraints(one_of: [:single, :multi, :judge, :essay])
      public?(true)
    end

    attribute :difficulty, :integer do
      default(3)
      constraints(min: 1, max: 5)
      public?(true)
    end

    attribute :stem, :string do
      allow_nil?(false)
      public?(true)
      description("题干（支持 markdown）")
    end

    attribute :options, {:array, :map} do
      default([])
      public?(true)
      description("[%{label: \"A\", text: \"…\", correct: true}, …]")
    end

    attribute :answer, :string do
      public?(true)
      description("essay 题的参考答案 / judge 题的 对|错")
    end

    attribute :explanation, :string do
      public?(true)
      description("答案解析")
    end

    attribute :media_url, :string do
      public?(true)
      description("配图/配视频 URL（存 OSS）")
    end

    attribute :tags, {:array, :string} do
      default([])
      public?(true)
    end

    attribute :knowledge_points, {:array, :string} do
      default([])
      public?(true)
    end

    attribute :status, :atom do
      default(:active)
      constraints(one_of: [:active, :archived])
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :bank, TcmEdu.Quiz.QuestionBank do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :created_by, TcmEdu.Accounts.User do
      public?(true)
      description("出题人")
    end
  end

  code_interface do
    define(:list_questions, action: :read)
    define(:get_question, action: :read, get_by: [:id])
    define(:create_question, action: :create)
    define(:update_question, action: :update)
    define(:delete_question, action: :destroy)
    define(:list_questions_by_bank, action: :list_by_bank)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :type,
        :difficulty,
        :stem,
        :options,
        :answer,
        :explanation,
        :media_url,
        :tags,
        :knowledge_points,
        :bank_id
      ])

      change(relate_actor(:created_by))
    end

    update :update do
      primary?(true)

      accept([
        :type,
        :difficulty,
        :stem,
        :options,
        :answer,
        :explanation,
        :media_url,
        :tags,
        :knowledge_points
      ])
    end

    read :list_by_bank do
      description("某题库下的题目（教师端）")
      argument(:bank_id, :uuid, allow_nil?: false)
      filter(expr(bank_id == ^arg(:bank_id)))
    end

    update :archive do
      description("软删除题目")
      accept([])
      change(set_attribute(:status, :archived))
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
      authorize_if(expr(created_by_id == ^actor(:id)))
    end

    policy action_type(:destroy) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(expr(created_by_id == ^actor(:id)))
    end
  end
end
