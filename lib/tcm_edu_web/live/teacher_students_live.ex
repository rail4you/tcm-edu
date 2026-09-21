defmodule TcmEduWeb.TeacherStudentsLive do
  @moduledoc """
  Teacher's student roster at `/teacher/students`: all students in the
  teacher's tenant with a live keyword filter.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.Accounts.User

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @page_size 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "我的学生")
     |> assign(:keyword, "")
     |> assign(:page, 1)
     |> load_students()}
  end

  @impl true
  def handle_event("search", %{"keyword" => keyword}, socket) do
    {:noreply, socket |> assign(:keyword, String.trim(keyword)) |> assign(:page, 1)}
  end

  def handle_event("page", %{"page" => page}, socket) do
    page =
      case Integer.parse(page) do
        {n, _} when n >= 1 -> min(n, total_pages(socket.assigns.students, socket.assigns.keyword))
        _ -> 1
      end

    {:noreply, assign(socket, :page, page)}
  end

  defp student_initial(%{name: name}) when is_binary(name) and byte_size(name) > 0 do
    name |> String.trim() |> String.first() |> String.upcase()
  end

  defp student_initial(%{email: email}) when is_binary(email) and byte_size(email) > 0 do
    email |> String.trim() |> String.first() |> String.upcase()
  end

  defp student_initial(_), do: "S"

  defp filtered(students, ""), do: students

  defp filtered(students, keyword) do
    kw = String.downcase(keyword)

    Enum.filter(students, fn student ->
      String.contains?(String.downcase(to_string(student.email)), kw) or
        String.contains?(String.downcase(student.name || ""), kw)
    end)
  end

  defp page_size, do: @page_size

  defp page_students(students, keyword, page) do
    students
    |> filtered(keyword)
    |> Enum.slice((page - 1) * @page_size, @page_size)
  end

  defp total_pages(students, keyword) do
    total = students |> filtered(keyword) |> length()
    max(1, ceil(total / @page_size))
  end

  defp total_count(students, keyword), do: students |> filtered(keyword) |> length()

  defp format_date(nil), do: "-"

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d")
  end

  defp format_date(date), do: to_string(date)

  defp load_students(socket) do
    teacher = socket.assigns.current_teacher

    students =
      try do
        User
        |> Ash.Query.for_read(:list_students, %{},
          actor: teacher.actor,
          tenant: teacher.tenant
        )
        |> Ash.read!()
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      rescue
        _ -> []
      end

    assign(socket, :students, students)
  end
end
