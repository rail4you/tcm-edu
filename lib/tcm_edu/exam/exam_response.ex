defmodule TcmEdu.Exam.ExamResponse do
  @moduledoc """
  考试单题作答（租户域）：`assignment × question` 的一条答案。

  * 客观题（单选/多选/判断）：`submit` 时自动判分，`is_correct` + `score`
    （答对记该题分值，答错 0 分）。
  * 主观题（简答）：不自动判分，`is_correct` 为 nil，`score` 由教师
    `grade_essay` 手动写入。

  同一道题在同一份作答里只能有一条记录（`identity` 保证，重复提交即更新）。
  """

  use Ash.Resource,
    domain: TcmEdu.Exam,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  multitenancy do
    strategy :context
  end

  postgres do
    table("exam_responses")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :answer, :string do
      public?(true)
      description("学生提交的答案")
    end

    attribute :is_correct, :boolean do
      public?(true)
    end

    attribute :score, :decimal do
      public?(true)
    end

    attribute :graded, :boolean do
      default(false)
      public?(true)
      description("主观题是否已被教师批改")
    end

    attribute :comment, :string do
      public?(true)
      description("教师批注")
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :assignment, TcmEdu.Exam.ExamAssignment do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :question, TcmEdu.Quiz.Question do
      allow_nil?(false)
      public?(true)
    end
  end

  identities do
    identity(:unique_assignment_question, [:assignment_id, :question_id])
  end

  code_interface do
    define(:list_exam_responses, action: :read)
    define(:submit_exam_response, action: :submit)
    define(:grade_essay_response, action: :grade_essay)
  end

  actions do
    defaults([:read])

    create :submit do
      primary?(true)
      upsert?(true)
      upsert_identity(:unique_assignment_question)
      description("学生提交单题答案；客观题自动判分")
      accept([:assignment_id, :question_id, :answer])
      change(TcmEdu.Exam.Changes.AutoGradeResponse)
    end

    update :grade_essay do
      description("教师批改主观题（评分 + 批注），并重算该作答总分")
      require_atomic?(false)
      accept([:score, :comment])
      change(TcmEdu.Exam.Changes.GradeEssay)
    end

    read :by_assignment do
      description("某作答下的全部答案")
      argument(:assignment_id, :uuid, allow_nil?: false)
      filter(expr(assignment_id == ^arg(:assignment_id)))
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
      authorize_if(expr(assignment.student_id == ^actor(:id)))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    policy action(:submit) do
      authorize_if(actor_present())
    end

    policy action(:grade_essay) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end
  end
end
