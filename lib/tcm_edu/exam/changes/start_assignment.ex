defmodule TcmEdu.Exam.Changes.StartAssignment do
  @moduledoc """
  学生开始作答：`assigned → in_progress`，记录 `started_at`。

  仅在 `assigned` 状态下可开始；已开始 / 已交卷会拒绝。
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case changeset.data.status do
        :assigned ->
          changeset
          |> Ash.Changeset.force_change_attribute(:status, :in_progress)
          |> Ash.Changeset.force_change_attribute(:started_at, DateTime.utc_now())

        :in_progress ->
          changeset

        _ ->
          Ash.Changeset.add_error(changeset, "该考试已交卷或已完成，不能再次开始")
      end
    end)
  end
end
