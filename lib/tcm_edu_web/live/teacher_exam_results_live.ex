defmodule TcmEduWeb.TeacherExamResultsLive do
  @moduledoc """
  考试结果 at `/teacher/exams/:id/results`.

  列出某试卷的全部作答记录与得分，支持教师对简答题逐题批改
  （评分 + 批注），并可一键完成整份批改。分数实时重算。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.Exam.{Exam, ExamAssignment}

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:exam_id, params["id"])
     |> assign(:page_title, "考试结果")
     |> assign(:grading, nil)
     |> assign(:grade_form, %{})
     |> load_exam()
     |> load_assignments()}
  end

  @impl true
  def handle_event("open-grade", %{"id" => assignment_id}, socket) do
    teacher = socket.assigns.current_teacher

    assignment =
      try do
        ExamAssignment
        |> Ash.Query.filter(id == ^assignment_id)
        |> Ash.Query.load(responses: [:question])
        |> Ash.read_one!(actor: teacher.actor, tenant: teacher.tenant)
      rescue
        _ -> nil
      end

    if assignment && assignment.status in [:submitted, :graded] do
      {:noreply,
       socket
       |> assign(:grading, assignment)
       |> assign(:grade_form, essay_form(assignment))}
    else
      {:noreply, put_flash(socket, :error, "该作答尚未交卷，无法批改")}
    end
  end

  def handle_event("close-grade", _params, socket) do
    {:noreply, socket |> assign(:grading, nil) |> assign(:grade_form, %{})}
  end

  def handle_event("validate-grade", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save-essay", %{"grade" => params}, socket) do
    teacher = socket.assigns.current_teacher
    response_id = params["response_id"]

    score =
      case Float.parse(to_string(params["score"] || "")) do
        {value, _} -> value
        :error -> nil
      end

    cond do
      is_nil(response_id) ->
        {:noreply, put_flash(socket, :error, "缺少作答记录")}

      is_nil(score) or score < 0 ->
        {:noreply, put_flash(socket, :error, "请填写有效的得分")}

      true ->
        case find_response(socket, response_id) do
          nil ->
            {:noreply, put_flash(socket, :error, "作答记录不存在")}

          response ->
            case response
                 |> Ash.Changeset.for_update(
                   :grade_essay,
                   %{
                     score: Decimal.new(score),
                     comment: empty_to_nil(params["comment"])
                   },
                   actor: teacher.actor,
                   tenant: teacher.tenant
                 )
                 |> Ash.update() do
              {:ok, _} ->
                {:noreply,
                 socket
                 |> put_flash(:info, "已评分")
                 |> reload_grading()
                 |> load_assignments()}

              {:error, error} ->
                {:noreply, put_flash(socket, :error, ash_message(error))}
            end
        end
    end
  end

  def handle_event("finish-grading", %{"id" => assignment_id}, socket) do
    teacher = socket.assigns.current_teacher

    case Enum.find(socket.assigns.assignments, &(&1.id == assignment_id)) do
      %ExamAssignment{status: :submitted} = assignment ->
        case assignment
             |> Ash.Changeset.for_update(:grade, %{},
               actor: teacher.actor,
               tenant: teacher.tenant
             )
             |> Ash.update() do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "批改完成")
             |> load_assignments()}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, ash_message(error))}
        end

      %ExamAssignment{} ->
        {:noreply, put_flash(socket, :error, "只有已交卷的作答才能完成批改")}

      _ ->
        {:noreply, put_flash(socket, :error, "作答记录不存在")}
    end
  end

  # ── loading ───────────────────────────────────────────────

  defp load_exam(socket) do
    teacher = socket.assigns.current_teacher

    exam =
      try do
        Exam
        |> Ash.Query.filter(id == ^socket.assigns.exam_id)
        |> Ash.Query.load([:total_questions, :total_score])
        |> Ash.read_one!(actor: teacher.actor, tenant: teacher.tenant)
      rescue
        _ -> nil
      end

    assign(socket, :exam, exam)
  end

  defp load_assignments(socket) do
    teacher = socket.assigns.current_teacher

    assignments =
      try do
        ExamAssignment
        |> Ash.Query.for_read(:list_by_exam, %{exam_id: socket.assigns.exam_id},
          actor: teacher.actor,
          tenant: teacher.tenant
        )
        |> Ash.Query.load(:student)
        |> Ash.read!()
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      rescue
        _ -> []
      end

    assign(socket, :assignments, assignments)
  end

  defp reload_grading(socket) do
    if socket.assigns.grading do
      teacher = socket.assigns.current_teacher

      assignment =
        try do
          ExamAssignment
          |> Ash.Query.filter(id == ^socket.assigns.grading.id)
          |> Ash.Query.load(responses: [:question])
          |> Ash.read_one!(actor: teacher.actor, tenant: teacher.tenant)
        rescue
          _ -> nil
        end

      if assignment do
        socket
        |> assign(:grading, assignment)
        |> assign(:grade_form, essay_form(assignment))
      else
        assign(socket, :grading, nil)
      end
    else
      socket
    end
  end

  defp find_response(socket, response_id) do
    ((socket.assigns.grading && socket.assigns.grading.responses) || [])
    |> Enum.find(&(&1.id == response_id))
  end

  # ── helpers ───────────────────────────────────────────────

  defp essay_questions(%ExamAssignment{} = assignment) do
    (assignment.responses || [])
    |> Enum.filter(&(&1.question.type == :essay))
    |> Enum.sort_by(& &1.inserted_at)
  end

  defp essay_form(assignment) do
    Map.new(essay_questions(assignment), fn response ->
      {response.id,
       %{
         "score" => if(response.score, do: Decimal.to_string(response.score), else: ""),
         "comment" => response.comment || ""
       }}
    end)
  end

  defp status_badge(:assigned), do: "badge-ghost"
  defp status_badge(:in_progress), do: "badge-info"
  defp status_badge(:submitted), do: "badge-warning"
  defp status_badge(:graded), do: "badge-success"
  defp status_badge(_), do: "badge-ghost"

  defp status_text(:assigned), do: "待作答"
  defp status_text(:in_progress), do: "作答中"
  defp status_text(:submitted), do: "待批改"
  defp status_text(:graded), do: "已批改"
  defp status_text(_), do: "未知"

  defp fmt_score(nil), do: "-"
  defp fmt_score(%Decimal{} = d), do: Decimal.to_string(d)
  defp fmt_score(n), do: to_string(n)

  defp format_time(nil), do: "-"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M")

  defp student_initial(%{name: name}) when is_binary(name) and byte_size(name) > 0 do
    name |> String.trim() |> String.first() |> String.upcase()
  end

  defp student_initial(%{email: email}) when is_binary(email) and byte_size(email) > 0 do
    email |> String.trim() |> String.first() |> String.upcase()
  end

  defp student_initial(_), do: "S"

  defp student_name(assignment) do
    (assignment.student && (assignment.student.name || to_string(assignment.student.email))) ||
      "—"
  end

  defp student_email(assignment) do
    (assignment.student && to_string(assignment.student.email)) || "—"
  end

  defp count_by(assignments, status), do: Enum.count(assignments, &(&1.status == status))

  defp avg_total(assignments) do
    graded = Enum.filter(assignments, &(&1.total_score != nil))

    if graded == [],
      do: nil,
      else:
        graded
        |> Enum.map(& &1.total_score)
        |> Enum.reduce(&Decimal.add/2)
        |> then(&Decimal.div(&1, length(graded)))
  end

  defp fmt_avg(nil), do: "-"

  defp fmt_avg(%Decimal{} = d) do
    d |> Decimal.round(1) |> Decimal.to_string()
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: String.trim(value)

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
