defmodule TcmEduWeb.TeacherExamAssignLive do
  @moduledoc """
  试卷分配 at `/teacher/exams/:id/assign`.

  学生表格 + checkbox 批量多选：支持关键词筛选、分页、当前页全选/反选，
  一键把试卷批量分配给选中学生；已分配的学生自动跳过并在表格中标出。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Exam.{Exam, ExamAssignment}

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @page_size 10

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:exam_id, params["id"])
     |> assign(:page_title, "分配试卷")
     |> assign(:keyword, "")
     |> assign(:page, 1)
     |> assign(:selected, MapSet.new())
     |> load_exam()
     |> load_students()}
  end

  @impl true
  def handle_event("search", %{"keyword" => keyword}, socket) do
    {:noreply, socket |> assign(keyword: String.trim(keyword), page: 1)}
  end

  def handle_event("page", %{"page" => page}, socket) do
    page =
      case Integer.parse(page) do
        {n, _} when n >= 1 ->
          min(n, total_pages(socket.assigns.students, socket.assigns.keyword))

        _ ->
          1
      end

    {:noreply, assign(socket, :page, page)}
  end

  def handle_event("toggle-student", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected, id) do
        MapSet.delete(socket.assigns.selected, id)
      else
        MapSet.put(socket.assigns.selected, id)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("toggle-all", %{"checked" => checked}, socket) do
    page_ids =
      page_ids(socket.assigns.students, socket.assigns.keyword, socket.assigns.page)

    selected =
      if checked == "true" do
        Enum.reduce(page_ids, socket.assigns.selected, &MapSet.put(&2, &1))
      else
        Enum.reduce(page_ids, socket.assigns.selected, &MapSet.delete(&2, &1))
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("assign-selected", _params, socket) do
    teacher = socket.assigns.current_teacher
    student_ids = MapSet.to_list(socket.assigns.selected)

    cond do
      student_ids == [] ->
        {:noreply, put_flash(socket, :error, "请先勾选要分配的学生")}

      socket.assigns.exam == nil ->
        {:noreply, put_flash(socket, :error, "试卷不存在")}

      socket.assigns.exam.status != :published ->
        {:noreply, put_flash(socket, :error, "试卷尚未发布，不能分配")}

      true ->
        case Exam.bulk_assign(%{exam_id: socket.assigns.exam.id, student_ids: student_ids},
               actor: teacher.actor,
               tenant: teacher.tenant
             ) do
          {:ok, %{assigned: assigned, skipped: skipped}} ->
            {:noreply,
             socket
             |> assign(:selected, MapSet.new())
             |> load_students()
             |> put_flash(
               :info,
               "已分配 #{assigned} 名学生" <>
                 if(skipped > 0, do: "，跳过 #{skipped} 名已分配的学生", else: "")
             )}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, err_message(error))}
        end
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

  defp load_students(socket) do
    teacher = socket.assigns.current_teacher

    students =
      try do
        User
        |> Ash.Query.for_read(:list_students, %{}, actor: teacher.actor, tenant: teacher.tenant)
        |> Ash.read!()
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      rescue
        _ -> []
      end

    assigned_ids =
      if socket.assigns.exam do
        try do
          ExamAssignment
          |> Ash.Query.for_read(:list_by_exam, %{exam_id: socket.assigns.exam.id},
            actor: teacher.actor,
            tenant: teacher.tenant
          )
          |> Ash.read!()
          |> Enum.map(& &1.student_id)
        rescue
          _ -> []
        end
      else
        []
      end

    assigned = MapSet.new(assigned_ids)

    socket
    |> assign(:students, students)
    |> assign(:assigned_students, assigned)
    |> assign(:selected, MapSet.new())
  end

  # ── filtering / pagination ────────────────────────────────

  defp filtered(students, ""), do: students

  defp filtered(students, keyword) do
    kw = String.downcase(keyword)

    Enum.filter(students, fn student ->
      String.contains?(String.downcase(to_string(student.email)), kw) or
        String.contains?(String.downcase(student.name || ""), kw)
    end)
  end

  defp page_students(students, keyword, page) do
    students
    |> filtered(keyword)
    |> Enum.slice((page - 1) * @page_size, @page_size)
  end

  defp page_size, do: @page_size

  defp total_pages(students, keyword) do
    total = students |> filtered(keyword) |> length()
    max(1, ceil(total / @page_size))
  end

  defp total_count(students, keyword), do: students |> filtered(keyword) |> length()

  defp page_ids(students, keyword, page),
    do: Enum.map(page_students(students, keyword, page), & &1.id)

  defp all_page_selected?(page_ids, selected) do
    page_ids != [] and Enum.all?(page_ids, &MapSet.member?(selected, &1))
  end

  # ── display helpers ───────────────────────────────────────

  defp student_initial(%{name: name}) when is_binary(name) and byte_size(name) > 0 do
    name |> String.trim() |> String.first() |> String.upcase()
  end

  defp student_initial(%{email: email}) when is_binary(email) and byte_size(email) > 0 do
    email |> String.trim() |> String.first() |> String.upcase()
  end

  defp student_initial(_), do: "S"

  defp format_date(nil), do: "-"
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  defp format_date(date), do: to_string(date)

  defp status_text(:draft), do: "草稿"
  defp status_text(:published), do: "已发布"
  defp status_text(:closed), do: "已关闭"
  defp status_text(_), do: "未知"

  defp status_badge(:draft), do: "badge-ghost"
  defp status_badge(:published), do: "badge-success"
  defp status_badge(:closed), do: "badge-warning"
  defp status_badge(_), do: "badge-ghost"

  defp err_message(error) do
    Exception.message(error)
  rescue
    _ -> inspect(error)
  end
end
