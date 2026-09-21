defmodule TcmEdu.Quiz.QuestionBank do
  @moduledoc """
  题库（租户域）：一组题目的集合，属于某个租户。

  每个租户可以有多个题库，按学科（subject）组织。题库与题目的关系：
  `Question.bank_id -> QuestionBank.id`。

  多租户：`multitenancy :context`，查询/变更必须带租户上下文。
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
    table("question_banks")
    repo(TcmEdu.Repo)
  end

  typescript do
    type_name("QuestionBank")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
      description("题库名称")
    end

    attribute :description, :string do
      public?(true)
    end

    attribute :subject, :atom do
      constraints(
        one_of: [
          :traditional_chinese_medicine,
          :western_medicine,
          :anatomy,
          :physiology,
          :pathology,
          :pharmacology,
          :clinical,
          :nursing,
          :public_health,
          :other
        ]
      )

      public?(true)
      description("学科分类")
    end

    attribute :is_public, :boolean do
      default(false)
      public?(true)
      description("是否为公共题库（对所有学生可见）")
    end

    attribute :visible_after_enrollment, :boolean do
      default(false)
      public?(true)
      description("仅对已选相应课程的学生开放（保留扩展）")
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    has_many :questions, TcmEdu.Quiz.Question do
      destination_attribute(:bank_id)
      public?(true)
    end
  end

  aggregates do
    count(:total_questions, :questions)
  end

  calculations do
    calculate :question_count, :integer, expr(total_questions) do
      public?(true)
    end
  end

  code_interface do
    define(:list_question_banks, action: :read)
    define(:get_question_bank, action: :read, get_by: [:id])
    define(:create_question_bank, action: :create)
    define(:update_question_bank, action: :update)
    define(:delete_question_bank, action: :destroy)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:name, :description, :subject, :is_public, :visible_after_enrollment])
    end

    update :update do
      primary?(true)
      accept([:name, :description, :subject, :is_public, :visible_after_enrollment])
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
