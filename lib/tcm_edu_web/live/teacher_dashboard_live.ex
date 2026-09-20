defmodule TcmEduWeb.TeacherDashboardLive do
  @moduledoc """
  Teacher home at `/teacher`: course status stats, recent courses and
  quick actions in an asymmetrical grid.
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
     |> assign(:page_subtitle, greeting(teacher))
     |> assign(:stats, stats)
     |> assign(:recent, Enum.take(courses, 5))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.teacher_shell
        current_teacher={@current_teacher}
        current_page={:dashboard}
        page_title="工作台"
        page_subtitle={@page_subtitle}
      >
        <:page_actions>
          <.link navigate="/teacher/courses/new" class="btn btn-primary btn-sm" id="new-course-btn">
            <.icon name="hero-plus" class="size-4" /> 创建课程
          </.link>
        </:page_actions>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
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

        <div class="grid grid-cols-1 items-start gap-6 xl:grid-cols-3">
          <div class="card bg-base-100 shadow-sm xl:col-span-2">
            <div class="card-body gap-2 p-4 sm:p-6">
              <div class="flex items-center justify-between gap-2">
                <p class="font-medium">最近更新的课程</p>
                <.link navigate="/teacher/courses" class="link link-primary text-xs">全部课程 →</.link>
              </div>
              <div class="overflow-x-auto">
                <table class="table table-pin-rows">
                  <thead>
                    <tr>
                      <th>课程</th>
                      <th>状态</th>
                      <th class="text-right tabular-nums">课时</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={course <- @recent} class="hover:bg-base-200">
                      <td>
                        <.link navigate={"/teacher/courses/#{course.id}/edit"} class="link-hover link font-medium">
                          {course.title}
                        </.link>
                      </td>
                      <td><.status_badge status={course.status} /></td>
                      <td class="text-right tabular-nums">{course.lesson_count || 0}</td>
                    </tr>
                    <tr :if={@recent == []}>
                      <td colspan="100%">
                        <div class="flex flex-col items-center gap-2 py-8">
                          <.icon name="hero-book-open" class="size-8 text-base-content/40" />
                          <p class="text-sm text-base-content/60">还没有课程，先创建第一门吧</p>
                          <.link navigate="/teacher/courses/new" class="btn btn-sm btn-primary">
                            创建课程
                          </.link>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <div class="flex flex-col gap-6">
            <div class="card bg-base-100 shadow-sm">
              <div class="card-body gap-2 p-4 sm:p-6">
                <p class="font-medium">备课流程</p>
                <ul class="steps steps-vertical">
                  <li class="step step-primary text-sm">创建课程</li>
                  <li class="step step-primary text-sm">添加章节与课时</li>
                  <li class="step text-sm">发布，学生即可选课</li>
                </ul>
                <.link navigate="/teacher/courses" class="btn btn-soft btn-sm mt-2">
                  前往我的课程 →
                </.link>
              </div>
            </div>
            <div class="card bg-primary text-primary-content shadow-sm">
              <div class="card-body gap-2 p-4 sm:p-6">
                <p class="flex items-center gap-2 font-medium">
                  <.icon name="hero-sparkles" class="size-5" /> 没灵感？
                </p>
                <p class="text-sm opacity-80">用 AI 备课生成大纲，一键存为课程草稿。</p>
                <.link navigate="/teacher/ai/lesson-plan" class="btn btn-sm border-0 bg-base-100">
                  试试 AI 备课
                </.link>
              </div>
            </div>
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
      <div class="card-body gap-2 p-4 sm:p-6">
        <div class="flex items-center justify-between gap-2">
          <p class="font-medium">{@title}</p>
          <span class="flex size-10 items-center justify-center rounded-box bg-primary/10 text-primary">
            <.icon name={@icon} class="size-5" />
          </span>
        </div>
        <p class={["text-3xl font-semibold tabular-nums", @tone]}>{@value}</p>
        <p :if={@hint} class="text-xs text-base-content/60">{@hint}</p>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_badge(assigns) do
    ~H"""
    <span :if={@status == :draft} class="badge badge-soft badge-ghost">草稿</span>
    <span :if={@status == :published} class="badge badge-soft badge-success">已发布</span>
    <span :if={@status == :archived} class="badge badge-soft badge-warning">已下架</span>
    """
  end

  defp greeting(%{name: name}), do: "#{name}，今天也要带好每一位学生"

  defp list_my_courses(teacher) do
    Course
    |> Ash.Query.for_read(:list_by_teacher, %{teacher_id: teacher.id},
      actor: teacher.actor,
      tenant: teacher.tenant
    )
    |> Ash.Query.load([:lesson_count])
    |> Ash.read!()
    |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
  rescue
    _ -> []
  end
end
