defmodule TcmEduWeb.TeacherExamBuildLive do
  @moduledoc """
  试卷组卷 at `/teacher/exams/:id/build`.

  左侧选择题库，右侧已选题目；可调整每题分值、上移/下移顺序、移除题目，
  满题后可一键发布。数据实时落库（`TcmEdu.Exam.ExamQuestion`）。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.Exam.{Exam, ExamQuestion}
  alias TcmEdu.Quiz.{Question, QuestionBank}

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @default_score 10

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:exam_id, params["id"])
     |> assign(:page_title, "试卷组卷")
     |> assign(:selected_bank_id, nil)
     |> assign(:type_filter, "all")
     |> assign(:difficulty_filter, "all")
     |> assign(:deleting, nil)
     |> load_exam()
     |> load_banks()}
  end

  @impl true
  def handle_event("select-bank", %{"bank_id" => id}, socket) do
    {:noreply, socket |> assign(selected_bank_id: id) |> load_bank_questions()}
  end

  def handle_event("filter-type", %{"type" => type}, socket) do
    {:noreply, assign(socket, :type_filter, type)}
  end

  def handle_event("filter-difficulty", %{"difficulty" => difficulty}, socket) do
    {:noreply, assign(socket, :difficulty_filter, difficulty)}
  end

  def handle_event("add-question", %{"id" => question_id}, socket) do
    teacher = socket.assigns.current_teacher
    exam = socket.assigns.exam

    next_position =
      (exam.exam_questions || [])
      |> Enum.map(&(&1.position || 0))
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)

    attrs = %{
      exam_id: exam.id,
      question_id: question_id,
      position: next_position,
      score: @default_score
    }

    case ExamQuestion.create_exam_question(attrs, actor: teacher.actor, tenant: teacher.tenant) do
      {:ok, _} ->
        {:noreply, socket |> load_exam() |> put_flash(:info, "已加入试卷")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  def handle_event("remove-question", %{"id" => exam_question_id}, socket) do
    teacher = socket.assigns.current_teacher

    case find_exam_question(socket, exam_question_id) do
      %ExamQuestion{} = eq ->
        case Ash.destroy(eq, actor: teacher.actor, tenant: teacher.tenant) do
          :ok -> {:noreply, socket |> load_exam() |> renumber() |> put_flash(:info, "已从试卷移除")}
          {:error, error} -> {:noreply, put_flash(socket, :error, ash_message(error))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "题目不存在")}
    end
  end

  def handle_event("update-score", %{"id" => id, "score" => score}, socket) do
    teacher = socket.assigns.current_teacher

    case Float.parse(score) do
      {value, _} when value > 0 ->
        case find_exam_question(socket, id) do
          %ExamQuestion{} = eq ->
            eq
            |> Ash.Changeset.for_update(:update, %{score: Decimal.new(value)},
              actor: teacher.actor,
              tenant: teacher.tenant
            )
            |> Ash.update()
            |> case do
              {:ok, _} -> {:noreply, load_exam(socket)}
              {:error, error} -> {:noreply, put_flash(socket, :error, ash_message(error))}
            end

          _ ->
            {:noreply, put_flash(socket, :error, "题目不存在")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "分值必须是正数")}
    end
  end

  def handle_event("move-up", %{"id" => id}, socket), do: move(socket, id, :up)
  def handle_event("move-down", %{"id" => id}, socket), do: move(socket, id, :down)

  def handle_event("publish", _params, socket) do
    teacher = socket.assigns.current_teacher
    exam = socket.assigns.exam

    cond do
      (exam.exam_questions || []) == [] ->
        {:noreply, put_flash(socket, :error, "请先至少加入一道题目")}

      true ->
        case exam
             |> Ash.Changeset.for_update(:publish, %{},
               actor: teacher.actor,
               tenant: teacher.tenant
             )
             |> Ash.update() do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "试卷已发布，可去分配学生")
             |> push_navigate(to: "/teacher/exams/#{exam.id}/assign")}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, ash_message(error))}
        end
    end
  end

  def handle_event("confirm-remove", %{"id" => id}, socket) do
    {:noreply, assign(socket, :deleting, find_exam_question(socket, id))}
  end

  def handle_event("close-remove", _params, socket) do
    {:noreply, assign(socket, :deleting, nil)}
  end

  # ── 移动顺序 ──────────────────────────────────────────────

  defp move(socket, id, direction) do
    teacher = socket.assigns.current_teacher
    ordered = ordered_questions(socket.assigns.exam)

    case Enum.find_index(ordered, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "题目不存在")}

      index ->
        target =
          case direction do
            :up when index > 0 -> index - 1
            :down when index < length(ordered) - 1 -> index + 1
            _ -> nil
          end

        if target == nil do
          {:noreply, socket}
        else
          current = Enum.at(ordered, index)
          other = Enum.at(ordered, target)

          {:ok, _} = set_position(current, target + 1, teacher)
          {:ok, _} = set_position(other, index + 1, teacher)

          {:noreply, load_exam(socket)}
        end
    end
  end

  defp set_position(%ExamQuestion{} = eq, position, teacher) do
    eq
    |> Ash.Changeset.for_update(:update, %{position: position},
      actor: teacher.actor,
      tenant: teacher.tenant
    )
    |> Ash.update()
  end

  # 删除后把剩余题目位置重新编号，保证 1..N 连续
  defp renumber(socket) do
    teacher = socket.assigns.current_teacher

    socket.assigns.exam.exam_questions
    |> Enum.sort_by(&(&1.position || 0))
    |> Enum.with_index(1)
    |> Enum.each(fn {eq, position} ->
      if (eq.position || 0) != position do
        set_position(eq, position, teacher)
      end
    end)

    load_exam(socket)
  end

  # ── loading ───────────────────────────────────────────────

  defp load_exam(socket) do
    teacher = socket.assigns.current_teacher

    exam =
      try do
        Exam
        |> Ash.Query.filter(id == ^socket.assigns.exam_id)
        |> Ash.Query.load(exam_questions: [:question])
        |> Ash.Query.load([:total_questions, :total_score])
        |> Ash.read_one!(actor: teacher.actor, tenant: teacher.tenant)
      rescue
        _ -> nil
      end

    assign(socket, :exam, exam)
  end

  defp load_banks(socket) do
    teacher = socket.assigns.current_teacher

    banks =
      try do
        QuestionBank
        |> Ash.Query.for_read(:read, %{}, actor: teacher.actor, tenant: teacher.tenant)
        |> Ash.Query.load([:question_count])
        |> Ash.read!()
        |> Enum.sort_by(& &1.name)
      rescue
        _ -> []
      end

    socket
    |> assign(:banks, banks)
    |> assign(:bank_questions, [])
  end

  defp load_bank_questions(socket) do
    teacher = socket.assigns.current_teacher

    questions =
      if socket.assigns.selected_bank_id do
        try do
          Question
          |> Ash.Query.for_read(:list_by_bank, %{bank_id: socket.assigns.selected_bank_id},
            actor: teacher.actor,
            tenant: teacher.tenant
          )
          |> Ash.Query.filter(status == :active)
          |> Ash.read!()
          |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
        rescue
          _ -> []
        end
      else
        []
      end

    assign(socket, :bank_questions, questions)
  end

  # ── helpers ───────────────────────────────────────────────

  defp ordered_questions(nil), do: []

  defp ordered_questions(exam) do
    (exam.exam_questions || [])
    |> Enum.sort_by(&(&1.position || 0))
  end

  defp total_score(nil), do: Decimal.new(0)

  defp total_score(exam) do
    ordered_questions(exam)
    |> Enum.reduce(Decimal.new(0), fn eq, acc ->
      Decimal.add(acc, eq.score || Decimal.new(0))
    end)
  end

  defp in_exam?(exam, question_id) do
    Enum.any?(exam.exam_questions || [], &(&1.question_id == question_id))
  end

  defp filtered_questions(bank_questions, type_filter, difficulty_filter) do
    bank_questions
    |> then(fn list ->
      case type_filter do
        "all" -> list
        type -> Enum.filter(list, &(&1.type == type))
      end
    end)
    |> then(fn list ->
      case difficulty_filter do
        "all" ->
          list

        d ->
          {d, _} = Integer.parse(d)
          Enum.filter(list, &(&1.difficulty == d))
      end
    end)
  end

  defp find_exam_question(socket, id) do
    Enum.find(socket.assigns.exam.exam_questions || [], &(&1.id == id))
  end

  defp question_type_label(:single), do: "单选"
  defp question_type_label(:multi), do: "多选"
  defp question_type_label(:judge), do: "判断"
  defp question_type_label(:essay), do: "简答"
  defp question_type_label(other), do: to_string(other)

  defp difficulty_badge(1), do: "badge-info"
  defp difficulty_badge(2), do: "badge-info"
  defp difficulty_badge(3), do: "badge-warning"
  defp difficulty_badge(4), do: "badge-warning"
  defp difficulty_badge(5), do: "badge-error"
  defp difficulty_badge(_), do: "badge-ghost"

  defp status_text(:draft), do: "草稿"
  defp status_text(:published), do: "已发布"
  defp status_text(:closed), do: "已关闭"
  defp status_text(_), do: "未知"

  defp fmt_score(%Decimal{} = d), do: Decimal.to_string(d)
  defp fmt_score(n), do: to_string(n)

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
