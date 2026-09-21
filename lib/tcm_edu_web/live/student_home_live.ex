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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.student_shell current_student={@current_student} current_page={:home} unread_count={@unread_count}>
        <section class="hero bg-base-200/30">
          <div class="hero-content max-w-6xl flex-col py-12 lg:flex-row-reverse lg:gap-12">
            <div class="grid max-w-md grid-cols-2 gap-4">
              <div class="card bg-base-100 shadow-sm">
                <div class="card-body items-center gap-1 p-4 text-center">
                  <p class="text-3xl font-semibold tabular-nums">{@courses |> Enum.map(&(&1.lesson_count || 0)) |> Enum.sum()}</p>
                  <p class="text-xs text-base-content/60">精选课时</p>
                </div>
              </div>
              <div class="card bg-base-100 shadow-sm">
                <div class="card-body items-center gap-1 p-4 text-center">
                  <p class="text-3xl font-semibold tabular-nums">{length(@teachers)}</p>
                  <p class="text-xs text-base-content/60">一线教师</p>
                </div>
              </div>
              <div class="card bg-base-100 shadow-sm">
                <div class="card-body items-center gap-1 p-4 text-center">
                  <p class="text-3xl font-semibold tabular-nums">{length(@courses)}</p>
                  <p class="text-xs text-base-content/60">热门课程</p>
                </div>
              </div>
              <div class="card bg-base-100 shadow-sm">
                <div class="card-body items-center gap-1 p-4 text-center">
                  <p class="text-3xl font-semibold tabular-nums">{@courses |> Enum.map(&(&1.student_count || 0)) |> Enum.sum()}</p>
                  <p class="text-xs text-base-content/60">在学人次</p>
                </div>
              </div>
            </div>
            <div class="max-w-xl">
              <p class="text-xs font-semibold uppercase tracking-widest text-primary">中医教育数字化</p>
              <p class="mt-2 text-4xl font-semibold leading-tight">系统学中医<br />从这里开始</p>
              <p class="mt-4 text-sm text-base-content/60">
                从基础理论到临床精进，选课、看课、进度跟踪，全程免费起步。
              </p>
              <div class="mt-6 flex flex-wrap gap-2">
                <.link navigate="/courses" class="btn btn-primary">浏览课程</.link>
                <.link
                  navigate={if @current_student, do: "/my-learning", else: "/login"}
                  class="btn btn-soft"
                >
                  {if @current_student, do: "继续学习", else: "登录"}
                </.link>
              </div>
            </div>
          </div>
        </section>

        <div class="mx-auto w-full max-w-6xl px-4 sm:px-6">
          <section class="py-8">
            <.section_head eyebrow="因材施教" title="课程分类" desc="从基础理论到临床精进，按需选课" />
            <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
              <div :for={category <- @categories} class="card bg-base-100 shadow-sm">
                <.link navigate={"/courses?category_id=#{category.id}"} class="card-body items-center gap-1 p-4 text-center">
                  <p class="font-medium">{category.name}</p>
                </.link>
              </div>
              <div :if={@categories == []} class="col-span-full">
                <p class="text-center text-sm text-base-content/60">分类筹备中</p>
              </div>
            </div>
          </section>

          <section class="py-8" id="courses">
            <.section_head eyebrow="热门推荐" title="大家都在学" desc="按在学人数排序的热门课程，免费试看先行" />
            <div :if={@courses != []} class="grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
              <.course_card :for={course <- @courses} course={course} id={"home-course-#{course.id}"} />
            </div>
            <p :if={@courses == []} class="rounded-box bg-base-200/30 px-6 py-10 text-center text-sm text-base-content/60">
              课程正在筹备中，敬请期待。
            </p>
            <p :if={!@current_student and @courses != []} class="mt-6 text-center text-sm text-base-content/60">
              登录后即可选课学习，进度云端同步。
              <.link navigate="/login" class="link link-primary ml-1">去登录 →</.link>
            </p>
          </section>

          <section :if={@teachers != []} class="py-8">
            <.section_head eyebrow="师者传道" title="名师风采" desc="一线教师精讲每一门课" />
            <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <div :for={teacher <- @teachers} class="card bg-base-100 shadow-sm">
                <div class="card-body items-center gap-1 p-4 text-center">
                  <span class="flex size-12 items-center justify-center rounded-full bg-neutral text-neutral-content">
                    {teacher.name |> String.first() |> String.upcase()}
                  </span>
                  <p class="font-medium">{teacher.name}</p>
                  <p class="text-xs text-base-content/60">{teacher.job_title || teacher.school || "教师"}</p>
                  <p class="line-clamp-2 text-xs text-base-content/60">{teacher.bio}</p>
                </div>
              </div>
            </div>
          </section>
        </div>

        <section class="mt-8 bg-primary text-primary-content">
          <div class="mx-auto flex w-full max-w-6xl flex-col items-center gap-4 px-4 py-12 text-center sm:px-6">
            <p class="text-2xl font-semibold md:text-3xl">今天，就开始你的中医学习之旅</p>
            <p class="max-w-xl text-sm opacity-80">注册即学：选课、看课、进度跟踪，全程免费起步。</p>
            <.link
              navigate={if @current_student, do: "/my-learning", else: "/login"}
              class="btn border-0 bg-base-100"
            >
              {if @current_student, do: "继续学习", else: "登录"}
            </.link>
          </div>
        </section>
      </.student_shell>
    </Layouts.app>
    """
  end

  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  attr :desc, :string, default: nil

  defp section_head(assigns) do
    ~H"""
    <div class="mb-6 text-center">
      <p class="text-xs font-semibold uppercase tracking-widest text-primary">{@eyebrow}</p>
      <p class="mt-2 text-2xl font-semibold md:text-3xl">{@title}</p>
      <p :if={@desc} class="mx-auto mt-2 max-w-xl text-sm text-base-content/60">{@desc}</p>
    </div>
    """
  end

  defp list_popular do
    Course
    |> Ash.Query.for_read(:list_popular, %{}, tenant: @tenant, authorize?: false)
    |> Ash.Query.load([:cover_image_url, :lesson_count, :student_count])
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
