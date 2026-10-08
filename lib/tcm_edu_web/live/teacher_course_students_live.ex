defmodule TcmEduWeb.TeacherCourseStudentsLive do
  @moduledoc """
  Course roster management at `/teacher/courses/:id/students`.

  The owning teacher (or a tenant admin) can add students to a course and
  remove existing enrollments. Added students immediately see the course on
  their `/my-learning` page.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Courses.Course
  alias TcmEdu.Enrollment.Enrollment

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @impl true
  def mount(%{"id" => course_id}, _session, socket) do
    teacher = socket.assigns.current_teacher

    case load_course(course_id, teacher) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "课程不存在或无权管理")
         |> push_navigate(to: "/teacher/courses")}

      course ->
        {:ok,
         socket
         |> assign(:course, course)
         |> assign(:course_id, course_id)
         |> assign(:keyword, "")
         |> assign(:students, list_students(teacher))
         |> load_roster()}
    end
  end

  @impl true
  def handle_event("search", %{"keyword" => keyword}, socket) do
    {:noreply, assign(socket, :keyword, String.trim(keyword))}
  end

  def handle_event("add-student", %{"id" => user_id}, socket) do
    teacher = socket.assigns.current_teacher

    result =
      Enrollment
      |> Ash.Changeset.for_create(
        :enroll_student,
        %{course_id: socket.assigns.course_id, user_id: user_id},
        actor: teacher.actor,
        tenant: teacher.tenant
      )
      |> Ash.create()

    case result do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "已添加学生") |> load_roster()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  def handle_event("remove-student", %{"id" => id}, socket) do
    teacher = socket.assigns.current_teacher

    case find_enrollment(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "选课记录不存在")}

      enrollment ->
        result =
          enrollment
          |> Ash.Changeset.for_update(:cancel, %{})
          |> Ash.update(actor: teacher.actor, tenant: teacher.tenant)

        case result do
          {:ok, _} ->
            {:noreply, socket |> put_flash(:info, "已移除学生") |> load_roster()}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, ash_message(error))}
        end
    end
  end

  # ─── helpers ────────────────────────────────────────────────

  defp load_course(id, teacher) do
    Course
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.load([:cover_image_url, :student_count])
    |> Ash.read_one(actor: teacher.actor, tenant: teacher.tenant)
    |> case do
      {:ok, nil} -> nil
      {:ok, course} -> if can_manage?(course, teacher), do: course, else: nil
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp can_manage?(_course, %{role: "tenant_admin"}), do: true
  defp can_manage?(course, %{id: id}), do: course.teacher_id == id

  defp load_roster(socket) do
    teacher = socket.assigns.current_teacher
    course_id = socket.assigns.course_id

    roster =
      Enrollment
      |> Ash.Query.filter(course_id == ^course_id and status == :active)
      |> Ash.Query.load([:user])
      |> Ash.read!(actor: teacher.actor, tenant: teacher.tenant)
      |> Enum.sort_by(& &1.enrolled_at, {:desc, DateTime})

    assign(socket, :roster, roster)
  rescue
    _ -> assign(socket, :roster, [])
  end

  defp list_students(teacher) do
    User
    |> Ash.Query.for_read(:list_students, %{},
      actor: teacher.actor,
      tenant: teacher.tenant
    )
    |> Ash.read!()
    |> Enum.sort_by(&String.downcase(&1.name || to_string(&1.email)))
  rescue
    _ -> []
  end

  defp find_enrollment(socket, id), do: Enum.find(socket.assigns.roster, &(&1.id == id))

  # 未在「已选」名单内的学生（用于「添加学生」面板）
  defp available_students(students, roster) do
    enrolled_ids = MapSet.new(roster, & &1.user_id)
    Enum.reject(students, &MapSet.member?(enrolled_ids, &1.id))
  end

  defp filtered(students, ""), do: students

  defp filtered(students, keyword) do
    kw = String.downcase(keyword)

    Enum.filter(students, fn student ->
      String.contains?(String.downcase(student.name || ""), kw) or
        String.contains?(String.downcase(to_string(student.email)), kw)
    end)
  end

  defp student_name(%{name: name}) when is_binary(name) and byte_size(name) > 0, do: name
  defp student_name(%{email: email}), do: to_string(email)
  defp student_name(_), do: "学生"

  defp student_initial(student) do
    student |> student_name() |> String.trim() |> String.first() |> String.upcase()
  end

  defp format_date(nil), do: "-"

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")

  defp format_date(value), do: to_string(value)

  defp ash_message(%Ash.Error.Invalid{} = error) do
    error.errors
    |> Enum.map(&Exception.message/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("；")
  end

  defp ash_message(%Ash.Error.Forbidden{}), do: "没有权限执行该操作"
  defp ash_message(error), do: Exception.message(error)
end
