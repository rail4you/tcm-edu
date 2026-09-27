defmodule TcmEdu.Exam.Changes.GradeEssay do
  @moduledoc """
  教师批改主观题：写入得分 + 批注，并重算该作答的主观分与总分。

  批改后作答状态不变（`submitted` 或 `graded` 均保持），分数实时更新。
  """

  use Ash.Resource.Change

  require Ash.Query

  alias TcmEdu.Exam.{ExamAssignment, ScoreCalculator}

  @impl true
  def change(changeset, _opts, _context) do
    changeset =
      Ash.Changeset.before_action(changeset, fn changeset ->
        case Ash.Changeset.get_attribute(changeset, :score) do
          nil ->
            Ash.Changeset.add_error(changeset, "请填写本题得分")

          score ->
            changeset
            |> Ash.Changeset.force_change_attribute(:graded, true)
            |> Ash.Changeset.force_change_attribute(:is_correct, nil)
            |> Ash.Changeset.force_change_attribute(:score, score)
        end
      end)

    Ash.Changeset.after_action(changeset, fn _changeset, response ->
      recompute_assignment(response)
      {:ok, response}
    end)
  end

  defp recompute_assignment(%{assignment_id: assignment_id, __metadata__: meta}) do
    tenant = meta[:tenant] || "tenant_default"
    scores = ScoreCalculator.compute(assignment_id, tenant)

    case Ash.get(ExamAssignment, assignment_id, tenant: tenant, authorize?: false) do
      {:ok, assignment} ->
        assignment
        |> Ash.Changeset.for_update(
          :update_scores,
          %{
            essay_score: scores.essay_score,
            total_score: scores.total_score
          },
          tenant: tenant,
          authorize?: false
        )
        |> Ash.update()

      _ ->
        :ok
    end
  end

  defp recompute_assignment(_), do: :ok
end
