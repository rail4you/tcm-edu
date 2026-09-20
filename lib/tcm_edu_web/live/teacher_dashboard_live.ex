defmodule TcmEduWeb.TeacherDashboardLive do
  @moduledoc """
  Teacher home at `/teacher`: course status stats plus the备课 flow card.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  alias TcmEdu.Courses.Course

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher
    courses = list_my_courses(teacher)

    stats = %{
      total: length(courses),
      draft: Enum.count(courses, &(&1.status == :draft)),
      published: Enum.count(courses, &(&1.status == :published)),
      archived: Enum.count(courses, &(&1.status == :archived))
    }

    {:ok,
     socket
     |> assign(:page_title, "工作台")
     |> assign(:stats, stats)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.teacher_shell current_teacher={@current_teacher} current_page={:dashboard} page_title="工作台">
        <:page_actions>
          <.link navigate="/teacher/courses/new" class="btn btn-primary" id="new-course-btn">
            <.icon name="hero-plus" class="size-4" /> 创建课程
          </.link>
        </:page_actions>

        <div class="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-4">
          <.stat_card title="全部课程" value={@stats.total} hint="我创建的课程" icon="hero-book-open" />
          <.stat_card title="草稿" value={@stats.draft} hint="备课中" icon="hero-pencil-square" />
          <.stat_card
            title="已发布"
            value={@stats.published}
            hint="学生可见"
            icon="hero-check-circle"
            tone="text-success"
          />
          <.stat_card title="已下架" value={@stats.archived} hint="历史课程" icon="hero-archive-box" />
        </div>

        <div class="card bg-base-100 shadow-sm">
          <div class="card-body gap-2.5 p-4 sm:p-6">
            <p class="font-medium">备课流程</p>
            <p class="text-sm text-base-content/60">
              创建课程 → 添加章节与课时 → 发布。上架后学生即可在学生端看到并选课。
            </p>
            <.link navigate="/teacher/courses" class="link link-primary text-sm">
              前往我的课程 →
            </.link>
          </div>
        </div>
      </.teacher_shell>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :hint, :string, default: nil
  attr :icon, :string, default: "hero-chart-bar"
  attr :tone, :string, default: nil

  defp stat_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body gap-2.5 p-4 sm:p-6">
        <div class="flex items-center justify-between gap-2">
          <p class="font-medium">{@title}</p>
          <span class="flex size-12 items-center justify-center rounded-full bg-base-200">
            <.icon name={@icon} class="size-5" />
          </span>
        </div>
        <p class={["text-3xl font-semibold tabular-nums", @tone]}>{@value}</p>
        <p :if={@hint} class="text-xs text-base-content/60">{@hint}</p>
      </div>
    </div>
    """
  end

  defp list_my_courses(teacher) do
    Course
    |> Ash.Query.for_read(:list_by_teacher, %{teacher_id: teacher.id},
      actor: teacher.actor,
      tenant: teacher.tenant
    )
    |> Ash.read!()
  rescue
    _ -> []
  end
end
