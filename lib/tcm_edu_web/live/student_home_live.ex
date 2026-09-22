defmodule TcmEduWeb.StudentHomeLive do
  @moduledoc """
  Public student home at `/`: hero, site stats, categories, popular
  courses, teachers and a registration CTA. Anonymous-friendly; logged-in
  students get an unread-notification dot.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1, course_card: 1]

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Courses.Course
  alias TcmEdu.Courses.CourseCategory
  alias TcmEdu.Notification.Notification

  on_mount {TcmEduWeb.StudentAuth, :fetch_student}

  @tenant "tenant_default"

  @impl true
  def mount(_params, _session, socket) do
    student = socket.assigns.current_student

    {:ok,
     socket
     |> assign(:page_title, "首页")
     |> assign(:courses, list_popular())
     |> assign(:categories, list_categories())
     |> assign(:teachers, list_teachers())
     |> assign(:unread_count, unread_count(student))}
  end

  defp list_popular do
    Course
    |> Ash.Query.for_read(:list_popular, %{}, tenant: @tenant, authorize?: false)
    |> Ash.Query.load([:cover_image_url, :lesson_count, :student_count, :category])
    |> Ash.read!()
  rescue
    _ -> []
  end

  defp list_categories do
    CourseCategory
    |> Ash.Query.for_read(:read, %{}, tenant: @tenant, authorize?: false)
    |> Ash.read!()
    |> Enum.sort_by(& &1.name)
  rescue
    _ -> []
  end

  defp list_teachers do
    User
    |> Ash.Query.for_read(:list_teacher_profiles, %{}, tenant: @tenant, authorize?: false)
    |> Ash.read!()
    |> Enum.filter(& &1.name)
    |> Enum.take(4)
  rescue
    _ -> []
  end

  defp unread_count(nil), do: 0

  defp unread_count(student) do
    Notification
    |> Ash.Query.for_read(:unread_count, %{},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.read!()
    |> length()
  rescue
    _ -> 0
  end
end
