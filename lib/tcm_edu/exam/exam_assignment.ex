defmodule TcmEdu.Exam.ExamAssignment do
  @moduledoc """
  考试分配（租户域）：一张已发布试卷 × 一名学生的一次作答。

  状态机：

    * `:assigned`    — 已分配，等待学生开始
    * `:in_progress` — 学生已开始作答（提交第一条答案时自动进入）
    * `:submitted`   — 学生已交卷，客观题已自动判分
    * `:graded`      — 教师已批改完毕（含主观题）

  分数：

    * `objective_score` — 客观题得分（答对计该题分值，答错 0 分）
    * `essay_score`     — 主观题得分（教师手动给分累加）
    * `total_score`     — 两者之和

  同一名学生同一张试卷只有一条记录（`identity` 保证）。
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
    table("exam_assignments")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :status, :atom do
      default(:assigned)
      public?(true)
      constraints(one_of: [:assigned, :in_progress, :submitted, :graded])
      description("作答状态")
    end

    attribute :assigned_at, :utc_datetime do
      default(&DateTime.utc_now/0)
      public?(true)
    end

    attribute :started_at, :utc_datetime do
      public?(true)
    end

    attribute :submitted_at, :utc_datetime do
      public?(true)
    end

    attribute :graded_at, :utc_datetime do
      public?(true)
    end

    attribute :objective_score, :decimal do
      default(0)
      public?(true)
    end

    attribute :essay_score, :decimal do
      default(0)
      public?(true)
    end

    attribute :total_score, :decimal do
      default(0)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :exam, TcmEdu.Exam.Exam do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :student, TcmEdu.Accounts.User do
      allow_nil?(false)
      public?(true)
      description("被分配的学生")
    end

    has_many :responses, TcmEdu.Exam.ExamResponse do
      destination_attribute(:assignment_id)
      public?(true)
    end
  end

  identities do
    identity(:unique_exam_student, [:exam_id, :student_id])
  end

  calculations do
    calculate :score_pct, :decimal, expr(total_score * 100) do
      public?(true)
      description("换算成百分制（便于展示，满分即总分）")
    end
  end

  code_interface do
    define(:list_exam_assignments, action: :read)
    define(:get_exam_assignment, action: :read, get_by: [:id])
    define(:assign_exam, action: :assign)
    define(:start_exam, action: :start)
    define(:submit_exam, action: :submit)
    define(:grade_exam, action: :grade)
    define(:my_exams, action: :my_exams)
  end

  actions do
    defaults([:read, :destroy])

    create :assign do
      primary?(true)
      upsert?(true)
      upsert_identity(:unique_exam_student)
      description("把试卷分配给一名学生（须为已发布状态）")
      accept([:exam_id, :student_id])
      change(TcmEdu.Exam.Changes.EnsureExamPublished)
    end

    update :start do
      description("学生开始作答：:assigned → :in_progress")
      require_atomic?(false)
      accept([])
      change(TcmEdu.Exam.Changes.StartAssignment)
    end

    update :submit do
      description("学生交卷：置 :submitted 并重算客观题得分")
      require_atomic?(false)
      accept([])
      change(TcmEdu.Exam.Changes.SubmitAssignment)
    end

    update :grade do
      description("教师完成批改：置 :graded 并重算总分（含主观题）")
      require_atomic?(false)
      accept([])
      change(TcmEdu.Exam.Changes.GradeAssignment)
    end

    update :update_scores do
      description("内部：逐题批注后写入重算得分，不改动状态")
      require_atomic?(false)
      accept([:essay_score, :total_score])
    end

    read :my_exams do
      description("当前学生被分配的全部考试")
      filter(expr(student_id == ^actor(:id)))
      prepare(build(sort: [inserted_at: :desc]))
    end

    read :list_by_exam do
      description("某试卷下的全部分配记录（教师端）")
      argument(:exam_id, :uuid, allow_nil?: false)
      filter(expr(exam_id == ^arg(:exam_id)))
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
      authorize_if(expr(student_id == ^actor(:id)))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    policy action_type(:create) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action([:start, :submit]) do
      authorize_if(expr(student_id == ^actor(:id)))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end

    policy action(:grade) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action_type(:destroy) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end
  end
end
