defmodule TcmEduWeb.StudentCoursesLive do
  @moduledoc """
  Public course catalog at `/courses` with keyword search and category /
  level filters.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1, course_card: 1]

  require Ash.Query

  alias TcmEdu.Courses.Course
  alias TcmEdu.Courses.CourseCategory

  on_mount {TcmEduWeb.StudentAuth, :fetch_student}

  @tenant "tenant_default"

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "课程")
     |> assign(:keyword, "")
     |> assign(:category_id, params["category_id"])
     |> assign(:level, "all")
     |> assign(:categories, list_categories())
     |> load_courses()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:category_id, params["category_id"])
     |> load_courses()}
  end

  @impl true
  def handle_event("search", %{"keyword" => keyword}, socket) do
    {:noreply, socket |> assign(:keyword, String.trim(keyword)) |> load_courses()}
  end

  def handle_event("filter-category", %{"category_id" => category_id}, socket) do
    {:noreply,
     socket
     |> assign(:category_id, empty_to_nil(category_id))
     |> load_courses()
     |> push_patch(to: courses_path(socket.assigns))}
  end

  def handle_event("filter-level", %{"level" => level}, socket)
      when level in ["all", "beginner", "intermediate", "advanced"] do
    {:noreply, assign(socket, :level, level)}
  end

  defp level_label("all"), do: "全部难度"
  defp level_label("beginner"), do: "初级"
  defp level_label("intermediate"), do: "中级"
  defp level_label("advanced"), do: "高级"

  defp visible(courses, "all"), do: courses
  defp visible(courses, level), do: Enum.filter(courses, &(to_string(&1.level) == level))

  defp courses_path(assigns) do
    case assigns.category_id do
      nil -> "/courses"
      id -> "/courses?category_id=#{id}"
    end
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp list_categories do
    CourseCategory
    |> Ash.Query.for_read(:read, %{}, tenant: @tenant, authorize?: false)
    |> Ash.read!()
    |> Enum.sort_by(& &1.name)
  rescue
    _ -> []
  end

  defp load_courses(socket) do
    %{keyword: keyword, category_id: category_id} = socket.assigns

    courses =
      try do
        Course
        |> Ash.Query.for_read(:list_published, %{}, tenant: @tenant, authorize?: false)
        |> Ash.Query.load([:cover_image_url, :lesson_count, :student_count])
        |> Ash.read!()
        |> Enum.filter(&match_keyword?(&1, keyword))
        |> Enum.filter(&match_category?(&1, category_id))
      rescue
        _ -> []
      end

    assign(socket, :courses, courses)
  end

  defp match_keyword?(_course, ""), do: true

  defp match_keyword?(course, keyword) do
    haystack = String.downcase("#{course.title} #{course.subtitle || ""}")
    String.contains?(haystack, String.downcase(keyword))
  end

  defp match_category?(_course, nil), do: true
  defp match_category?(course, category_id), do: course.category_id == category_id
end
