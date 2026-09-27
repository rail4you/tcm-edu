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
     |> assign(:grade_tab, "essay")
     |> assign(:max_scores, %{})
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
        |> Ash.Query.load(:student)
        |> Ash.read_one!(actor: teacher.actor, tenant: teacher.tenant)
      rescue
        _ -> nil
      end

    if assignment && assignment.status in [:submitted, :graded] do
      {:noreply,
       socket
       |> assign(:grading, assignment)
       |> assign(:grade_form, essay_form(assignment))
       |> assign(:grade_tab, "essay")
       |> assign(:max_scores, max_scores(socket.assigns.exam_id, teacher))}
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

  def handle_event("switch-grade-tab", %{"tab" => tab}, socket)
      when tab in ["objective", "essay"] do
    {:noreply, assign(socket, :grade_tab, tab)}
  end

  def handle_event("save-all-essays", %{"scores" => scores}, socket) do
    teacher = socket.assigns.current_teacher
    max_scores = socket.assigns.max_scores || %{}

    with {:ok, entries} <- parse_all_scores(socket, scores, max_scores) do
      results =
        Enum.map(entries, fn {response, score, comment} ->
          response
          |> Ash.Changeset.for_update(
            :grade_essay,
            %{score: score, comment: comment},
            actor: teacher.actor,
            tenant: teacher.tenant
          )
          |> Ash.update()
        end)

      errors = Enum.filter(results, &match?({:error, _}, &1))

      if errors == [] do
        {:noreply,
         socket
         |> put_flash(:info, "评分已保存，成绩已更新")
         |> assign(:grading, nil)
         |> assign(:grade_form, %{})
         |> load_assignments()}
      else
        {:noreply, put_flash(socket, :error, "部分保存失败，请重试")}
      end
    else
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("save-all-essays", _params, socket) do
    {:noreply, put_flash(socket, :error, "请填写每题得分")}
  end

  def handle_event("save-essay", %{"grade" => params}, socket) do
    teacher = socket.assigns.current_teacher
    response_id = params["response_id"]

    case find_response(socket, response_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "作答记录不存在")}

      response ->
        max = max_for(socket.assigns.max_scores || %{}, response.question_id)

        case parse_score(params["score"], max) do
          {:error, message} ->
            {:noreply, put_flash(socket, :error, message)}

          {:ok, score} ->
            case response
                 |> Ash.Changeset.for_update(
                   :grade_essay,
                   %{
                     score: score,
                     comment: empty_to_nil(params["comment"])
                   },
                   actor: teacher.actor,
                   tenant: teacher.tenant
                 )
                 |> Ash.update() do
              {:ok, _} ->
                {:noreply,
                 socket
                 |> put_flash(:info, "已评分，成绩已更新")
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
          |> Ash.Query.load(:student)
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

  defp essay_response?(%{question: %{type: :essay}}), do: true
  defp essay_response?(_), do: false

  defp objective_questions(%ExamAssignment{} = assignment) do
    (assignment.responses || [])
    |> Enum.reject(&essay_response?/1)
    |> Enum.sort_by(& &1.inserted_at)
  end

  defp response_correct_text(%{is_correct: true}), do: "正确"
  defp response_correct_text(%{is_correct: false}), do: "错误"
  defp response_correct_text(_), do: "—"

  defp essay_questions(%ExamAssignment{} = assignment) do
    (assignment.responses || [])
    |> Enum.filter(&essay_response?/1)
    |> Enum.sort_by(& &1.inserted_at)
  end

  defp max_scores(exam_id, teacher) do
    try do
      alias TcmEdu.Exam.ExamQuestion

      ExamQuestion
      |> Ash.Query.for_read(:read, %{},
        actor: teacher.actor,
        tenant: teacher.tenant
      )
      |> Ash.Query.filter(exam_id == ^exam_id)
      |> Ash.read!()
      |> Map.new(fn eq -> {eq.question_id, eq.score || Decimal.new(0)} end)
    rescue
      _ -> %{}
    end
  end

  defp max_for(max_scores, question_id) do
    Map.get(max_scores, question_id, Decimal.new(100))
  end

  defp parse_score(raw, max) do
    max_f =
      try do
        Decimal.to_float(max)
      rescue
        _ -> 100.0
      end

    case Float.parse(to_string(raw || "") |> String.trim()) do
      {value, _} when value < 0 ->
        {:error, "得分不能为负数"}

      {value, _} when value > max_f ->
        {:error, "得分不能高于本题满分（#{fmt_score(max)} 分）"}

      {value, _} ->
        rounded = Float.round(value * 2) / 2

        if abs(value - rounded) > 1.0e-9 do
          {:error, "得分最小步长为 0.5 分"}
        else
          {:ok, rounded |> Decimal.from_float() |> Decimal.round(1)}
        end

      :error ->
        {:error, "请填写有效的得分（0～#{fmt_score(max)}，步长 0.5）"}
    end
  end

  defp parse_all_scores(socket, scores, max_scores) do
    responses =
      case socket.assigns.grading do
        %ExamAssignment{} = grading ->
          (grading.responses || [])
          |> Enum.filter(&essay_response?/1)
          |> Enum.sort_by(& &1.inserted_at)

        _ ->
          []
      end

    Enum.reduce_while(responses, {:ok, []}, fn response, {:ok, acc} ->
      params = Map.get(scores, response.id, %{})
      max = max_for(max_scores, response.question_id)

      case parse_score(params["score"], max) do
        {:ok, score} ->
          {:cont, {:ok, [{response, score, empty_to_nil(params["comment"])} | acc]}}

        {:error, message} ->
          {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
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
  defp fmt_score(%Decimal{} = d), do: fmt_decimal(d)
  defp fmt_score(n) when is_float(n), do: fmt_decimal(Decimal.from_float(n))
  defp fmt_score(n) when is_integer(n), do: to_string(n)
  defp fmt_score(n), do: to_string(n)

  defp fmt_decimal(d) do
    rounded = Decimal.round(d, 1) |> Decimal.normalize()
    Decimal.to_string(rounded, :normal)
  end

  defp format_time(nil), do: "-"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M")

  defp student_initial(%{name: name}) when is_binary(name) and byte_size(name) > 0 do
    name |> String.trim() |> String.first() |> String.upcase()
  end

  defp student_initial(%{email: email}) when is_binary(email) and byte_size(email) > 0 do
    email |> String.trim() |> String.first() |> String.upcase()
  end

  defp student_initial(_), do: "S"

  defp student_name(%{student: %Ash.NotLoaded{}}), do: "—"

  defp student_name(assignment) do
    (assignment.student && (assignment.student.name || to_string(assignment.student.email))) ||
      "—"
  end

  defp student_email(%{student: %Ash.NotLoaded{}}), do: "—"

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
    d |> Decimal.round(1) |> fmt_decimal()
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
