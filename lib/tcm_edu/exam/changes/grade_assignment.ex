defmodule TcmEdu.Exam.Changes.GradeAssignment do
  @moduledoc """
  教师完成批改：置 `graded`、记录 `graded_at`，重算主观题得分与总分。

  需要作答已交卷（`:submitted`）才能进入 `:graded`。
  """

  use Ash.Resource.Change

  alias TcmEdu.Exam.ScoreCalculator

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case changeset.data.status do
        :submitted ->
          scores = ScoreCalculator.compute(changeset.data.id, changeset.tenant)

          changeset
          |> Ash.Changeset.force_change_attribute(:status, :graded)
          |> Ash.Changeset.force_change_attribute(:graded_at, DateTime.utc_now())
          |> Ash.Changeset.force_change_attribute(:essay_score, scores.essay_score)
          |> Ash.Changeset.force_change_attribute(:total_score, scores.total_score)

        _ ->
          Ash.Changeset.add_error(changeset, "只有已交卷的作答才能批改")
      end
    end)
  end
end
