defmodule TcmEduWeb.StudentExamsLive do
  @moduledoc """
  我的考试 at `/exams`.

  展示学生被分配的全部试卷（含作答状态与得分），点击进入答题页。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query

  alias TcmEdu.Exam.ExamAssignment

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "我的考试")
     |> assign(:unread_count, 0)
     |> load_assignments()}
  end

  defp load_assignments(socket) do
    student = socket.assigns.current_student

    assignments =
      try do
        ExamAssignment
        |> Ash.Query.for_read(:my_exams, %{}, actor: student.actor, tenant: student.tenant)
        |> Ash.Query.load(exam: [:total_questions, :total_score])
        |> Ash.read!()
      rescue
        _ -> []
      end

    assign(socket, :assignments, assignments)
  end

  # ── display helpers ───────────────────────────────────────

  defp status_badge(:assigned), do: "badge-info"
  defp status_badge(:in_progress), do: "badge-warning"
  defp status_badge(:submitted), do: "badge-ghost"
  defp status_badge(:graded), do: "badge-success"
  defp status_badge(_), do: "badge-ghost"

  defp status_text(:assigned), do: "待作答"
  defp status_text(:in_progress), do: "作答中"
  defp status_text(:submitted), do: "待批改"
  defp status_text(:graded), do: "已批改"
  defp status_text(_), do: "未知"

  defp subject_label(:traditional_chinese_medicine), do: "中医"
  defp subject_label(:western_medicine), do: "西医"
  defp subject_label(:anatomy), do: "解剖"
  defp subject_label(:physiology), do: "生理"
  defp subject_label(:pathology), do: "病理"
  defp subject_label(:pharmacology), do: "药理"
  defp subject_label(:clinical), do: "临床"
  defp subject_label(:nursing), do: "护理"
  defp subject_label(:public_health), do: "公卫"
  defp subject_label(:other), do: "其他"
  defp subject_label(other), do: to_string(other)

  defp fmt_score(nil), do: "-"
  defp fmt_score(%Decimal{} = d), do: Decimal.to_string(d)
  defp fmt_score(n), do: to_string(n)

  defp fmt_date(nil), do: "-"
  defp fmt_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  defp fmt_date(date), do: to_string(date)
end
