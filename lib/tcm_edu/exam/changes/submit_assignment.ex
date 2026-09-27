defmodule TcmEdu.Exam.Changes.SubmitAssignment do
  @moduledoc """
  学生交卷：置 `submitted`、记录 `submitted_at`，并按当前答案重算客观题得分。

  客观题得分在交卷时锁定；主观题得分在教师批改后累加（见 `GradeAssignment`）。
  """

  use Ash.Resource.Change

  alias TcmEdu.Exam.ScoreCalculator

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case changeset.data.status do
        status when status in [:assigned, :in_progress] ->
          scores = ScoreCalculator.compute(changeset.data.id, changeset.tenant)

          changeset
          |> Ash.Changeset.force_change_attribute(:status, :submitted)
          |> Ash.Changeset.force_change_attribute(:submitted_at, DateTime.utc_now())
          |> Ash.Changeset.force_change_attribute(:objective_score, scores.objective_score)
          |> Ash.Changeset.force_change_attribute(:total_score, scores.total_score)

        _ ->
          Ash.Changeset.add_error(changeset, "该考试不在可交卷状态")
      end
    end)
  end
end
