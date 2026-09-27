defmodule TcmEdu.Exam.Changes.AutoGradeResponse do
  @moduledoc """
  学生提交单题答案时的自动判分。

  * 校验作答归属本人（`assignment.student_id == actor.id`）且状态为
    `assigned` / `in_progress`（未交卷）；
  * 首次提交时把作答置为 `in_progress` 并记录 `started_at`；
  * 客观题（单选/多选/判断）调用 `TcmEdu.Quiz.Grading` 判分，
    答对记该题分值，答错 0 分；
  * 主观题（简答）仅保存答案，不判分。
  """

  use Ash.Resource.Change

  require Ash.Query

  alias TcmEdu.Exam.ExamAssignment
  alias TcmEdu.Exam.ExamQuestion
  alias TcmEdu.Quiz.{Grading, Question}

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      assignment_id = Ash.Changeset.get_attribute(changeset, :assignment_id)
      question_id = Ash.Changeset.get_attribute(changeset, :question_id)
      answer = Ash.Changeset.get_attribute(changeset, :answer)

      case do_grade(assignment_id, question_id, answer, context.actor, changeset.tenant) do
        {:ok, graded} ->
          changeset
          |> Ash.Changeset.force_change_attribute(:is_correct, graded.is_correct)
          |> Ash.Changeset.force_change_attribute(:score, graded.score)
          |> Ash.Changeset.force_change_attribute(:graded, false)

        {:error, message} ->
          Ash.Changeset.add_error(changeset, message)
      end
    end)
  end

  defp do_grade(assignment_id, question_id, answer, actor, tenant) do
    with {:ok, assignment} <- load_assignment(assignment_id, tenant),
         :ok <- ensure_own_active(assignment, actor),
         {:ok, question} <- load_question(question_id, tenant),
         {:ok, exam_question} <- load_exam_question(assignment, question_id, tenant),
         :ok <- maybe_start_assignment(assignment, tenant),
         {:ok, graded} <- grade(question, exam_question, answer) do
      {:ok, graded}
    end
  end

  # ── 加载 ─────────────────────────────────────────────────

  defp load_assignment(assignment_id, tenant) do
    case ExamAssignment
         |> Ash.Query.filter(id == ^assignment_id)
         |> Ash.read_one(tenant: tenant, authorize?: false) do
      {:ok, %ExamAssignment{} = assignment} -> {:ok, assignment}
      _ -> {:error, "作答记录不存在"}
    end
  end

  defp load_question(question_id, tenant) do
    case Ash.get(Question, question_id, tenant: tenant, authorize?: false) do
      {:ok, %Question{} = question} -> {:ok, question}
      _ -> {:error, "题目不存在"}
    end
  end

  defp load_exam_question(%ExamAssignment{exam_id: exam_id}, question_id, tenant) do
    case ExamQuestion
         |> Ash.Query.filter(exam_id == ^exam_id and question_id == ^question_id)
         |> Ash.read_one(tenant: tenant, authorize?: false) do
      {:ok, %ExamQuestion{} = eq} -> {:ok, eq}
      _ -> {:error, "本题不在该试卷中"}
    end
  end

  # ── 校验 ─────────────────────────────────────────────────

  defp ensure_own_active(%ExamAssignment{} = assignment, actor) do
    cond do
      is_nil(actor) ->
        {:error, "请先登录"}

      assignment.student_id != actor.id ->
        {:error, "只能作答分配给自己的考试"}

      assignment.status in [:submitted, :graded] ->
        {:error, "该考试已交卷，不能再作答"}

      true ->
        :ok
    end
  end

  # 首次提交 → 置为 in_progress
  defp maybe_start_assignment(%ExamAssignment{} = assignment, tenant) do
    if assignment.status == :assigned do
      case assignment
           |> Ash.Changeset.for_update(:start, %{}, tenant: tenant, authorize?: false)
           |> Ash.update() do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    else
      :ok
    end
  end

  # ── 判分 ─────────────────────────────────────────────────

  defp grade(%Question{type: type} = question, %ExamQuestion{score: eq_score}, answer)
       when type in [:single, :multi, :judge] do
    if is_binary(answer) and String.trim(answer) != "" do
      case Grading.grade(question, answer) do
        true ->
          {:ok, %{is_correct: true, score: eq_score || Decimal.new(0)}}

        false ->
          {:ok, %{is_correct: false, score: Decimal.new(0)}}

        nil ->
          {:ok, %{is_correct: nil, score: nil}}
      end
    else
      {:ok, %{is_correct: false, score: Decimal.new(0)}}
    end
  end

  defp grade(%Question{type: :essay}, _exam_question, _answer) do
    {:ok, %{is_correct: nil, score: nil}}
  end

  defp grade(_question, _exam_question, _answer), do: {:ok, %{is_correct: nil, score: nil}}
end
