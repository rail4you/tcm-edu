defmodule TcmEdu.Exam.Exam do
  @moduledoc """
  试卷（租户域）。

  * `status` — `:draft`（草稿，组卷中）→ `:published`（已发布，可分配）
    → `:closed`（已关闭，不可再分配）
  * `source` — `:manual`（从习题库手工组卷）/ `:ai`（AI 智能组卷）
  * `exam_questions` 是题目集合（带分值 / 顺序），`assignments` 是学生分配记录。

  发布后题目集合原则上不再修改；学生只能看到已发布的试卷。
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
    table("exams")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
      description("试卷名称")
    end

    attribute :description, :string do
      public?(true)
      description("试卷说明")
    end

    attribute :subject, :atom do
      default(:traditional_chinese_medicine)
      public?(true)

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

      description("学科分类")
    end

    attribute :status, :atom do
      default(:draft)
      public?(true)
      constraints(one_of: [:draft, :published, :closed])
      description("草稿 / 已发布 / 已关闭")
    end

    attribute :source, :atom do
      default(:manual)
      public?(true)
      constraints(one_of: [:manual, :ai])
      description("组卷方式：手工 / AI")
    end

    attribute :duration_minutes, :integer do
      default(60)
      constraints(min: 5, max: 600)
      public?(true)
      description("考试时长（分钟）")
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :created_by, TcmEdu.Accounts.User do
      public?(true)
      description("组卷人")
    end

    has_many :exam_questions, TcmEdu.Exam.ExamQuestion do
      destination_attribute(:exam_id)
      sort(position: :asc, inserted_at: :asc)
      public?(true)
    end

    has_many :assignments, TcmEdu.Exam.ExamAssignment do
      destination_attribute(:exam_id)
      public?(true)
    end
  end

  aggregates do
    count(:total_questions, :exam_questions)
    count(:assigned_count, :assignments)
    sum(:total_score, :exam_questions, :score)
  end

  code_interface do
    define(:list_exams, action: :read)
    define(:get_exam, action: :read, get_by: [:id])
    define(:create_exam, action: :create)
    define(:update_exam, action: :update)
    define(:publish_exam, action: :publish)
    define(:close_exam, action: :close)
    define(:delete_exam, action: :destroy)
    define(:bulk_assign, action: :bulk_assign)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:name, :description, :subject, :duration_minutes, :source])
      change(relate_actor(:created_by))
    end

    update :update do
      primary?(true)
      accept([:name, :description, :subject, :duration_minutes])
    end

    update :publish do
      description("发布试卷：从 :draft → :published")
      accept([])
      change(set_attribute(:status, :published))
    end

    update :close do
      description("关闭试卷：从 :published → :closed")
      accept([])
      change(set_attribute(:status, :closed))
    end

    action :bulk_assign, :map do
      description("批量把试卷分配给一组学生（已分配的学生自动跳过）")
      argument(:exam_id, :uuid, allow_nil?: false)
      argument(:student_ids, {:array, :uuid}, allow_nil?: false)

      run(fn input, context ->
        exam_id = input.arguments.exam_id
        student_ids = input.arguments.student_ids

        case load_exam(exam_id, context) do
          {:ok, exam} when exam.status == :published ->
            assign_batch(exam_id, student_ids, context)

          {:ok, _exam} ->
            {:error, "试卷尚未发布，不能分配给学生"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
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
      authorize_if(expr(status == :published))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action_type([:create, :destroy]) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action_type(:update) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action(:bulk_assign) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end
  end

  # ── bulk_assign 内部实现 ──────────────────────────────────

  defp load_exam(exam_id, context) do
    __MODULE__
    |> Ash.Query.filter(id == ^exam_id)
    |> Ash.read_one(tenant: context.tenant, authorize?: false)
  end

  defp assign_batch(exam_id, student_ids, context) do
    existing =
      TcmEdu.Exam.ExamAssignment
      |> Ash.Query.filter(exam_id == ^exam_id)
      |> Ash.Query.filter(student_id in ^student_ids)
      |> Ash.read(tenant: context.tenant, authorize?: false)
      |> case do
        {:ok, records} -> MapSet.new(records, & &1.student_id)
        _ -> MapSet.new()
      end

    {assigned, skipped} =
      Enum.reduce(student_ids, {0, 0}, fn student_id, {ok_count, skip_count} ->
        if MapSet.member?(existing, student_id) do
          {ok_count, skip_count + 1}
        else
          case create_assignment(exam_id, student_id, context) do
            {:ok, _} -> {ok_count + 1, skip_count}
            {:error, _} -> {ok_count, skip_count + 1}
          end
        end
      end)

    {:ok, %{assigned: assigned, skipped: skipped}}
  end

  defp create_assignment(exam_id, student_id, context) do
    TcmEdu.Exam.ExamAssignment
    |> Ash.Changeset.for_action(:assign, %{exam_id: exam_id, student_id: student_id},
      actor: context.actor,
      tenant: context.tenant
    )
    |> Ash.create()
  end
end
