defmodule TcmEdu.Enrollment.Changes.EnsureCoursePublished do
  @moduledoc """
  选课前置检查：课程必须已发布。

  必须是 `before_action` hook 而不能是 `validate`——create 的 validate
  跑在 `for_action` 时，此时 `changeset.tenant` 还没进来（tenant 在
  `Ash.create` 的 opts 里，验证阶段不可见），查库只能查到“课程不存在”。
  `before_action` 跑在 run 阶段，tenant 已就绪（已实测确认）。
  """

  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &ensure_published/1)
  end

  defp ensure_published(changeset) do
    course_id = Ash.Changeset.get_attribute(changeset, :course_id)

    case TcmEdu.Courses.Course
         |> Ash.Query.filter(id == ^course_id)
         |> Ash.read_one(tenant: changeset.tenant, authorize?: false) do
      {:ok, %{status: :published}} ->
        changeset

      {:ok, _} ->
        Ash.Changeset.add_error(changeset, field: :course_id, message: "只能选择已发布的课程")

      _ ->
        Ash.Changeset.add_error(changeset, field: :course_id, message: "课程不存在")
    end
  end
end
