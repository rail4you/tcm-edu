defmodule TcmEdu.Enrollment.Changes.EnsureTeacherCanEnroll do
  @moduledoc """
  教师/管理员为学生选课的前置检查：

    * 课程必须存在，且属于当前教师（`tenant_admin` 直接放行）
    * 目标用户必须是本租户的学生

  与 `EnsureCoursePublished` 同理，必须是 `before_action`（run 阶段
  `changeset.tenant` 才就绪），否则查库会因缺 tenant 而误判。
  """

  use Ash.Resource.Change

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Courses.Course

  @impl true
  def change(changeset, _opts, context) do
    actor = context.actor
    Ash.Changeset.before_action(changeset, &ensure_allowed(&1, actor))
  end

  defp ensure_allowed(changeset, actor) do
    tenant = changeset.tenant
    course_id = Ash.Changeset.get_attribute(changeset, :course_id)
    user_id = Ash.Changeset.get_attribute(changeset, :user_id)

    case fetch_course(course_id, tenant) do
      nil ->
        Ash.Changeset.add_error(changeset, field: :course_id, message: "课程不存在")

      course ->
        if can_manage?(course, actor) do
          case fetch_student(user_id, tenant) do
            {:ok, _user} ->
              changeset

            :error ->
              Ash.Changeset.add_error(changeset,
                field: :user_id,
                message: "只能添加本机构的学生"
              )
          end
        else
          Ash.Changeset.add_error(changeset, field: :course_id, message: "无权为该课程添加学生")
        end
    end
  end

  defp can_manage?(_course, %{role: :tenant_admin}), do: true

  defp can_manage?(course, actor) when not is_nil(actor) do
    course.teacher_id == Map.get(actor, :id)
  end

  defp can_manage?(_course, _actor), do: false

  defp fetch_course(nil, _tenant), do: nil

  defp fetch_course(course_id, tenant) do
    case Course
         |> Ash.Query.filter(id == ^course_id)
         |> Ash.read_one(tenant: tenant, authorize?: false) do
      {:ok, course} -> course
      _ -> nil
    end
  end

  defp fetch_student(nil, _tenant), do: :error

  defp fetch_student(user_id, tenant) do
    case User
         |> Ash.Query.filter(id == ^user_id)
         |> Ash.read_one(tenant: tenant, authorize?: false) do
      {:ok, %User{role: :student} = user} -> {:ok, user}
      _ -> :error
    end
  end
end
