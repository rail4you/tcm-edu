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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.student_shell current_student={@current_student} current_page={:courses}>
        <div class="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6">
          <p class="text-2xl font-semibold md:text-3xl">课程表</p>
          <p class="mt-1 text-sm text-base-content/60">已发布课程，免费试看先行</p>

          <form phx-change="search" phx-submit="search" class="mt-4 flex max-w-md gap-2">
            <input
              type="search"
              name="keyword"
              value={@keyword}
              placeholder="搜索课程标题"
              class="input input-bordered w-full"
              aria-label="搜索课程"
            />
          </form>

          <div class="mt-4 flex flex-wrap gap-2">
            <button
              class={["btn btn-sm", is_nil(@category_id) && "btn-active"]}
              phx-click="filter-category"
              phx-value-category_id=""
            >
              全部分类
            </button>
            <button
              :for={category <- @categories}
              class={["btn btn-sm", @category_id == category.id && "btn-active"]}
              phx-click="filter-category"
              phx-value-category_id={category.id}
            >
              {category.name}
            </button>
          </div>

          <div class="tabs tabs-boxed mt-4 w-fit" role="tablist" aria-label="按难度筛选">
            <button
              :for={level <- ["all", "beginner", "intermediate", "advanced"]}
              role="tab"
              class={["tab", @level == level && "tab-active"]}
              phx-click="filter-level"
              phx-value-level={level}
            >
              {level_label(level)}
            </button>
          </div>

          <div :if={visible(@courses, @level) != []} class="mt-6 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
            <.course_card
              :for={course <- visible(@courses, @level)}
              course={course}
              id={"catalog-course-#{course.id}"}
            />
          </div>
          <div :if={visible(@courses, @level) == []} class="mt-6 rounded-box bg-base-200/30 px-6 py-10 text-center">
            <.icon name="hero-book-open" class="size-8 text-base-content/40" />
            <p class="mt-2 text-sm text-base-content/60">没有找到匹配的课程，换个条件试试</p>
          </div>
        </div>
      </.student_shell>
    </Layouts.app>
    """
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
        |> Ash.Query.load([:lesson_count, :student_count])
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
