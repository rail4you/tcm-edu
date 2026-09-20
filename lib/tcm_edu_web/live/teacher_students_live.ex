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

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "我的学生")
     |> assign(:keyword, "")
     |> load_students()}
  end

  @impl true
  def handle_event("search", %{"keyword" => keyword}, socket) do
    {:noreply, assign(socket, :keyword, String.trim(keyword))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.teacher_shell
        current_teacher={@current_teacher}
        current_page={:students}
        page_title="我的学生"
        page_subtitle={"本机构共 #{length(@students)} 名学生"}
      >
        <:page_actions>
          <form phx-change="search" phx-submit="search">
            <label class="input input-bordered input-sm flex items-center gap-2">
              <.icon name="hero-magnifying-glass" class="size-4 text-base-content/60" />
              <input
                type="search"
                name="keyword"
                value={@keyword}
                placeholder="按邮箱 / 姓名筛选"
                class="grow"
                aria-label="按邮箱或姓名筛选学生"
              />
            </label>
          </form>
        </:page_actions>

        <div class="card bg-base-100 shadow-sm">
          <div class="card-body gap-2.5 p-4 sm:p-6">
            <div class="overflow-x-auto rounded-box border border-base-300">
              <table class="table table-zebra table-pin-rows">
                <thead>
                  <tr>
                    <th>邮箱</th>
                    <th>姓名</th>
                    <th>状态</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={student <- filtered(@students, @keyword)} class="hover:bg-base-200" id={"student-#{student.id}"}>
                    <td class="font-medium">{student.email}</td>
                    <td>{student.name || "-"}</td>
                    <td>
                      <span :if={student.status == :active} class="badge badge-soft badge-success">启用</span>
                      <span :if={student.status != :active} class="badge badge-soft badge-error">停用</span>
                    </td>
                  </tr>
                  <tr :if={filtered(@students, @keyword) == []}>
                    <td colspan="100%">
                      <div class="flex flex-col items-center gap-2 py-8">
                        <.icon name="hero-users" class="size-8 text-base-content/40" />
                        <p class="text-sm text-base-content/60">
                          {if @keyword == "", do: "还没有学生", else: "没有匹配的学生"}
                        </p>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </.teacher_shell>
    </Layouts.app>
    """
  end

  defp filtered(students, ""), do: students

  defp filtered(students, keyword) do
    kw = String.downcase(keyword)

    Enum.filter(students, fn student ->
      String.contains?(String.downcase(to_string(student.email)), kw) or
        String.contains?(String.downcase(student.name || ""), kw)
    end)
  end

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
