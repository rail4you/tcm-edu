defmodule TcmEduWeb.StudentExamTakeLive do
  @moduledoc """
  考试答题 / 结果 at `/exams/:id/take`.

  * 未交卷：逐题作答（单选/多选/判断/简答），每题自动保存并实时判分；
    「交卷」后锁定客观题得分。
  * 已交卷：展示得分明细与逐题对错、参考答案与解析。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query

  alias TcmEdu.Exam.{ExamAssignment, ExamResponse}

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) and socket.assigns.current_student do
      student = socket.assigns.current_student
      Phoenix.PubSub.subscribe(TcmEdu.PubSub, "notifications:#{student.tenant}:#{student.id}")
    end

    {:ok,
     socket
     |> assign(:exam_id, params["id"])
     |> assign(:page_title, "考试")
     |> assign(:confirm_submit, false)
     |> load_all()}
  end

  @impl true
  def handle_info({:exam_graded, %{exam_name: exam_name}}, socket) do
    {:noreply,
     socket
     |> load_all()
     |> put_flash(:info, "试卷《#{exam_name}》已批改，可查看成绩")}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("save-answer", params, socket) do
    case params["answer"] do
      answers when is_map(answers) and map_size(answers) > 0 ->
        {question_id, raw_answer} = hd(Map.to_list(answers))
        answer = normalize_answer(raw_answer)

        case save_answer(socket, question_id, answer) do
          :ok -> {:noreply, socket |> load_all() |> put_flash(:info, "答案已保存")}
          {:error, message} -> {:noreply, put_flash(socket, :error, message)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("open-submit", _params, socket) do
    {:noreply, assign(socket, :confirm_submit, true)}
  end

  def handle_event("close-submit", _params, socket) do
    {:noreply, assign(socket, :confirm_submit, false)}
  end

  def handle_event("submit-exam", _params, socket) do
    student = socket.assigns.current_student
    assignment = socket.assigns.assignment

    case assignment
         |> Ash.Changeset.for_update(:submit, %{}, actor: student.actor, tenant: student.tenant)
         |> Ash.update() do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "交卷成功，等待教师批改后可查看成绩")
         |> push_navigate(to: "/exams")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:confirm_submit, false)
         |> put_flash(:error, err_message(error))}
    end
  end

  # ── loading ───────────────────────────────────────────────

  defp save_answer(socket, question_id, answer) do
    student = socket.assigns.current_student
    assignment = socket.assigns.assignment

    cond do
      is_nil(assignment) ->
        {:error, "没有可作答的考试"}

      assignment.status in [:submitted, :graded] ->
        {:error, "考试已交卷"}

      true ->
        case ExamResponse.submit_exam_response(
               %{
                 assignment_id: assignment.id,
                 question_id: question_id,
                 answer: answer
               },
               actor: student.actor,
               tenant: student.tenant
             ) do
          {:ok, _} -> :ok
          {:error, error} -> {:error, err_message(error)}
        end
    end
  end

  defp normalize_answer(list) when is_list(list), do: list |> Enum.sort() |> Enum.join(",")
  defp normalize_answer(value), do: value

  defp load_all(socket) do
    student = socket.assigns.current_student

    assignment =
      try do
        ExamAssignment
        |> Ash.Query.filter(exam_id == ^socket.assigns.exam_id and student_id == ^student.id)
        |> Ash.Query.load(
          exam: [:total_questions, :total_score, exam_questions: [:question]],
          responses: []
        )
        |> Ash.read_one!(actor: student.actor, tenant: student.tenant)
      rescue
        _ -> nil
      end

    socket
    |> assign(:assignment, assignment)
    |> assign(:response_map, response_map(assignment))
  end

  defp response_map(nil), do: %{}

  defp response_map(%ExamAssignment{} = assignment) do
    Map.new(assignment.responses || [], &{&1.question_id, &1})
  end

  # ── display helpers ───────────────────────────────────────

  defp questions(%{exam: %{exam_questions: eqs}}),
    do: (eqs || []) |> Enum.sort_by(&(&1.position || 0))

  defp questions(_), do: []

  defp answered_count(nil, _response_map), do: 0
  defp answered_count(_assignment, nil), do: 0
  defp answered_count(_assignment, response_map), do: map_size(response_map)

  defp total_count(nil), do: 0
  defp total_count(assignment), do: length(questions(assignment))

  defp saved_answer(response_map, question_id) do
    case Map.get(response_map || %{}, question_id) do
      %{answer: answer} when is_binary(answer) -> answer
      _ -> ""
    end
  end

  defp saved_choices(response_map, question_id) do
    saved_answer(response_map, question_id)
    |> String.split(~r/[,\s、，;；]+/, trim: true)
    |> MapSet.new()
  end

  defp options_text(nil), do: []

  defp options_text(options) when is_list(options) do
    Enum.map(options, fn
      %{"label" => label, "text" => text} -> {label, text}
      %{label: label, text: text} -> {label, text}
      _ -> {"", ""}
    end)
  end

  defp options_text(_), do: []

  defp is_correct?(response_map, question_id) do
    case Map.get(response_map || %{}, question_id) do
      %{is_correct: value} when is_boolean(value) -> value
      _ -> nil
    end
  end

  defp type_label(:single), do: "单选"
  defp type_label(:multi), do: "多选"
  defp type_label(:judge), do: "判断"
  defp type_label(:essay), do: "简答"
  defp type_label(other), do: to_string(other)

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

  defp fmt_score(nil), do: "-"
  defp fmt_score(%Decimal{} = d), do: Decimal.to_string(d)
  defp fmt_score(n), do: to_string(n)

  defp err_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
