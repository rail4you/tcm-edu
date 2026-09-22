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

  defp load_enrollments(socket) do
    student = socket.assigns.current_student

    rows =
      try do
        Enrollment
        |> Ash.Query.for_read(:my_enrollments, %{},
          actor: student.actor,
          tenant: student.tenant
        )
        |> Ash.Query.load(course: [:cover_image_url], progress_records: [])
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
