defmodule TcmEdu.Exam.ExamQuestion do
  @moduledoc """
  试卷题目（租户域）：试卷与题目的关联，附带每题分值与顺序。

  * `position` — 题目在试卷中的顺序（1 起）
  * `score`    — 本题分值（客观题答对得满分，简答题由教师手动给分）

  同一道题不能重复出现在同一份试卷（`identity` 保证）。
  """

  use Ash.Resource,
    domain: TcmEdu.Exam,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("exam_questions")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :position, :integer do
      default(0)
      public?(true)
      description("题号，从 1 开始")
    end

    attribute :score, :decimal do
      default(10)
      constraints(min: 0.5, max: 100)
      public?(true)
      description("本题分值")
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :exam, TcmEdu.Exam.Exam do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :question, TcmEdu.Quiz.Question do
      allow_nil?(false)
      public?(true)
    end
  end

  identities do
    identity(:unique_exam_question, [:exam_id, :question_id])
  end

  code_interface do
    define(:list_exam_questions, action: :read)
    define(:get_exam_question, action: :read, get_by: [:id])
    define(:create_exam_question, action: :create)
    define(:update_exam_question, action: :update)
    define(:delete_exam_question, action: :destroy)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      upsert?(true)
      upsert_identity(:unique_exam_question)
      accept([:exam_id, :question_id, :position, :score])
    end

    update :update do
      primary?(true)
      accept([:position, :score])
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
