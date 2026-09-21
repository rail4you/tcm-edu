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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.student_shell current_student={@current_student} current_page={:courses}>
        <div :if={@not_found} class="mx-auto w-full max-w-6xl px-4 py-16 text-center sm:px-6">
          <.icon name="hero-exclamation-triangle" class="size-8 text-base-content/40" />
          <p class="mt-2 text-sm text-base-content/60">课程不存在或已下架</p>
          <.link navigate="/courses" class="btn btn-sm btn-primary mt-4">返回课程表</.link>
        </div>

        <div :if={!@not_found and @course} class="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6">
          <div class="breadcrumbs text-xs text-base-content/60">
            <ul>
              <li><.link navigate="/courses">课程</.link></li>
              <li>{@course.title}</li>
            </ul>
          </div>

          <div class="mt-2 grid gap-6 lg:grid-cols-3">
            <div class="flex flex-col gap-6 lg:col-span-2">
              <div>
                <p class="text-2xl font-semibold md:text-3xl">{@course.title}</p>
                <p class="mt-1 text-sm text-base-content/60">{@course.subtitle}</p>
                <div class="mt-3 flex flex-wrap gap-2">
                  <span class="badge badge-soft">{level_label(@course.level)}</span>
                  <span class="badge badge-soft badge-info">{@course.lesson_count || 0} 课时</span>
                  <span class="badge badge-soft badge-success">{@course.student_count || 0} 人在学</span>
                </div>
              </div>

              <figure :if={@course.cover_image_url} class="overflow-hidden rounded-box">
                <img src={@course.cover_image_url} alt={@course.title} class="aspect-[16/9] w-full object-cover" />
              </figure>

              <div :if={@course.description} class="card bg-base-100 shadow-sm">
                <div class="card-body gap-2 p-4 sm:p-6">
                  <p class="font-medium">课程介绍</p>
                  <p class="whitespace-pre-line text-sm text-base-content/80">{@course.description}</p>
                </div>
              </div>

              <div class="card bg-base-100 shadow-sm">
                <div class="card-body gap-2 p-4 sm:p-6">
                  <p class="font-medium">课程大纲</p>
                  <p :if={@course.chapters == []} class="text-sm text-base-content/60">大纲筹备中</p>
                  <div :for={{chapter, ci} <- Enum.with_index(@course.chapters || [], 1)} class="collapse collapse-arrow bg-base-200/30">
                    <input type="checkbox" checked={ci == 1} />
                    <p class="collapse-title font-medium">第 {ci} 章 · {chapter.title}</p>
                    <div class="collapse-content">
                      <ul class="flex flex-col gap-1">
                        <li
                          :for={{lesson, li} <- Enum.with_index(Enum.sort_by(chapter.lessons || [], &(&1.sort_order || 0)), 1)}
                          class="flex items-center gap-2 py-1 text-sm"
                        >
                          <span class="badge badge-soft badge-xs">{li}</span>
                          <p class="flex-1 truncate">{lesson.title}</p>
                          <span :if={lesson.is_free_preview} class="badge badge-soft badge-success badge-xs">试看</span>
                          <span :if={lesson.duration_seconds} class="text-xs tabular-nums text-base-content/60">
                            {div(lesson.duration_seconds, 60)} 分钟
                          </span>
                        </li>
                      </ul>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="flex flex-col gap-6">
              <div class="card bg-base-100 shadow-sm lg:sticky lg:top-20">
                <div class="card-body items-center gap-2 p-4 text-center sm:p-6">
                  <p class="text-3xl font-semibold tabular-nums">{price_label(@course.price_cents)}</p>
                  <button
                    :if={!@enrolled?}
                    class="btn btn-primary w-full"
                    phx-click="enroll"
                    id="enroll-btn"
                    phx-disable-with="选课中..."
                  >
                    {if @current_student, do: "立即选课", else: "登录后选课"}
                  </button>
                  <.link :if={@enrolled?} navigate={"/learn?course_id=#{@course.id}"} class="btn btn-primary w-full">
                    进入学习
                  </.link>
                  <p class="text-xs text-base-content/60">选课后进度云端同步，随时继续</p>
                </div>
              </div>

              <div :if={@course.teacher} class="card bg-base-100 shadow-sm">
                <div class="card-body items-center gap-1 p-4 text-center">
                  <span class="flex size-12 items-center justify-center rounded-full bg-neutral text-neutral-content">
                    {(@course.teacher.name || "?") |> String.first() |> String.upcase()}
                  </span>
                  <p class="font-medium">{@course.teacher.name}</p>
                  <p class="text-xs text-base-content/60">{@course.teacher.job_title || @course.teacher.school}</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </.student_shell>
    </Layouts.app>
    """
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
