defmodule TcmEdu.Exam.Changes.EnsureExamPublished do
  @moduledoc """
  校验被分配的试卷已发布（`:published`），否则拒绝分配。
  """

  use Ash.Resource.Change

  require Ash.Query

  alias TcmEdu.Exam.Exam

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Ash.Changeset.get_attribute(changeset, :exam_id) do
        nil ->
          Ash.Changeset.add_error(changeset, "缺少试卷")

        exam_id ->
          case load_exam(exam_id, changeset) do
            %Exam{status: :published} ->
              changeset

            _ ->
              Ash.Changeset.add_error(changeset, "试卷尚未发布，不能分配给学生")
          end
      end
    end)
  end

  defp load_exam(exam_id, changeset) do
    Exam
    |> Ash.Query.filter(id == ^exam_id)
    |> Ash.read_one(tenant: changeset.tenant, authorize?: false)
    |> case do
      {:ok, %Exam{} = exam} -> exam
      _ -> nil
    end
  end
end
