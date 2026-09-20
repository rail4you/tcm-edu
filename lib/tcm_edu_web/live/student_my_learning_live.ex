defmodule TcmEduWeb.StudentMyLearningLive do
  @moduledoc """
  Enrolled courses at `/my-learning` with overall progress bars, plus
  shortcuts to the mistake book and the notification center.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1, course_card: 1]

  require Ash.Query

  alias TcmEdu.Enrollment.Enrollment

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "我的学习")
     |> load_enrollments()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.student_shell current_student={@current_student} current_page={:my_learning}>
        <div class="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6">
          <p class="text-2xl font-semibold md:text-3xl">我的学习</p>
          <p class="mt-1 text-sm text-base-content/60">继续上次的进度，见证你的成长</p>

          <div class="mt-4 flex flex-wrap gap-2">
            <.link navigate="/my-learning/mistakes" class="btn btn-soft btn-sm">
              <.icon name="hero-book-open" class="size-4" /> 错题本（含 AI 解析）
            </.link>
            <.link navigate="/notifications" class="btn btn-soft btn-sm">
              <.icon name="hero-bell" class="size-4" /> 通知中心
            </.link>
          </div>

          <div :if={@rows != []} class="mt-6 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            <div :for={row <- @rows} class="relative">
              <.course_card
                course={row.course}
                id={"enrolled-#{row.enrollment_id}"}
                progress_pct={row.avg_pct}
              />
              <.link
                navigate={"/learn?course_id=#{row.course_id}"}
                class="btn btn-primary btn-sm absolute right-4 top-4 shadow-md"
              >
                继续学习
              </.link>
            </div>
          </div>

          <div :if={@rows == []} class="mt-6 rounded-box bg-base-200/30 px-6 py-12 text-center">
            <p class="text-lg font-semibold">还没有选课</p>
            <p class="mt-1 text-sm text-base-content/60">去课程表挑一门感兴趣的课开始吧。</p>
            <.link navigate="/courses" class="btn btn-primary mt-4">去选课</.link>
          </div>
        </div>
      </.student_shell>
    </Layouts.app>
    """
  end

  defp load_enrollments(socket) do
    student = socket.assigns.current_student

    rows =
      try do
        Enrollment
        |> Ash.Query.for_read(:my_enrollments, %{},
          actor: student.actor,
          tenant: student.tenant
        )
        |> Ash.Query.load([:course, :progress_records])
        |> Ash.read!()
        |> Enum.filter(&(&1.status == :active))
        |> Enum.filter(& &1.course)
        |> Enum.map(fn enrollment ->
          pcts = Enum.map(enrollment.progress_records || [], &(&1.progress_pct || 0))

          %{
            enrollment_id: enrollment.id,
            course_id: enrollment.course_id,
            course: enrollment.course,
            avg_pct: if(pcts == [], do: 0, else: round(Enum.sum(pcts) / length(pcts)))
          }
        end)
      rescue
        _ -> []
      end

    assign(socket, :rows, rows)
  end
end
