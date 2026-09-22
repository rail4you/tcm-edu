defmodule TcmEduWeb.StudentCourseDetailLive do
  @moduledoc """
  Public course detail at `/courses/:id`: hero, chapters/lessons outline
  (free-preview marked), teacher card and the enroll CTA. Anonymous
  visitors are prompted to log in before enrolling.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query

  alias TcmEdu.Courses.Course
  alias TcmEdu.Enrollment.Enrollment

  on_mount {TcmEduWeb.StudentAuth, :fetch_student}

  @tenant "tenant_default"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "课程详情")
     |> assign(:course_id, id)
     |> assign(:course, nil)
     |> assign(:not_found, false)
     |> assign(:enrolled?, false)
     |> load_course()}
  end

  @impl true
  def handle_event("enroll", _params, %{assigns: %{current_student: nil}} = socket) do
    {:noreply, push_navigate(socket, to: "/login")}
  end

  def handle_event("enroll", _params, socket) do
    student = socket.assigns.current_student

    case Enrollment
         |> Ash.Changeset.for_create(
           :enroll,
           %{course_id: socket.assigns.course_id},
           actor: student.actor,
           tenant: student.tenant
         )
         |> Ash.create() do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "选课成功，开始学习吧")
         |> push_navigate(to: "/learn?course_id=#{socket.assigns.course_id}")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  defp level_label(:beginner), do: "初级"
  defp level_label(:intermediate), do: "中级"
  defp level_label(:advanced), do: "高级"
  defp level_label(_), do: "-"

  defp price_label(nil), do: "-"
  defp price_label(0), do: "免费"
  defp price_label(cents), do: "¥#{:erlang.float_to_binary(cents / 100, decimals: 2)}"

  defp load_course(socket) do
    student = socket.assigns.current_student
    {actor, tenant} = if student, do: {student.actor, student.tenant}, else: {nil, @tenant}

    try do
      course =
        Course
        |> Ash.Query.filter(id == ^socket.assigns.course_id)
        |> Ash.Query.load([
          :cover_image_url,
          :lesson_count,
          :student_count,
          :teacher,
          chapters: [:lessons]
        ])
        |> Ash.read_one!(actor: actor, tenant: tenant, authorize?: student != nil)

      chapters = course.chapters |> Enum.sort_by(&(&1.sort_order || 0))

      socket
      |> assign(:course, %{course | chapters: chapters})
      |> assign(:not_found, false)
      |> assign(:enrolled?, enrolled?(student, socket.assigns.course_id))
    rescue
      _ -> assign(socket, course: nil, not_found: true, enrolled?: false)
    end
  end

  defp enrolled?(nil, _course_id), do: false

  defp enrolled?(student, course_id) do
    Enrollment
    |> Ash.Query.filter(user_id == ^student.id and course_id == ^course_id and status == :active)
    |> Ash.exists?(actor: student.actor, tenant: student.tenant)
  rescue
    _ -> false
  end

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "选课失败，请稍后重试"
  end
end
