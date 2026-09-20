defmodule TcmEduWeb.StudentNotificationsLive do
  @moduledoc """
  Notification center at `/notifications`: list, mark one / all as read.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query

  alias TcmEdu.Notification.Notification

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "通知中心")
     |> load_notifications()}
  end

  @impl true
  def handle_event("mark-read", %{"id" => id}, socket) do
    student = socket.assigns.current_student

    with notification when not is_nil(notification) <-
           Enum.find(socket.assigns.notifications, &(&1.id == id)),
         {:ok, _} <-
           notification
           |> Ash.Changeset.for_update(:mark_read, %{},
             actor: student.actor,
             tenant: student.tenant
           )
           |> Ash.update() do
      {:noreply, load_notifications(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "操作失败，请稍后重试")}
    end
  end

  def handle_event("mark-all-read", _params, socket) do
    student = socket.assigns.current_student
    unread = Enum.filter(socket.assigns.notifications, &is_nil(&1.read_at))

    results =
      Enum.map(unread, fn notification ->
        notification
        |> Ash.Changeset.for_update(:mark_read, %{},
          actor: student.actor,
          tenant: student.tenant
        )
        |> Ash.update()
      end)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:noreply, socket |> put_flash(:info, "已全部标为已读") |> load_notifications()}
    else
      {:noreply, socket |> put_flash(:error, "部分通知标记失败") |> load_notifications()}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.student_shell
        current_student={@current_student}
        current_page={:notifications}
        unread_count={unread_count(@notifications)}
      >
        <div class="mx-auto w-full max-w-4xl px-4 py-8 sm:px-6">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div>
              <p class="text-2xl font-semibold md:text-3xl">通知中心</p>
              <p class="mt-1 text-sm text-base-content/60">
                {unread_text(unread_count(@notifications))}
              </p>
            </div>
            <button
              :if={unread_count(@notifications) > 0}
              class="btn btn-soft btn-sm"
              phx-click="mark-all-read"
              phx-disable-with="处理中..."
            >
              <.icon name="hero-check" class="size-4" /> 全部标为已读
            </button>
          </div>

          <div :for={notification <- @notifications} class="card mt-4 bg-base-100 shadow-sm">
            <div class="card-body gap-1 p-4 sm:p-6">
              <div class="flex items-center gap-2">
                <span class={["badge badge-soft", type_badge(notification.type)]}>{type_label(notification.type)}</span>
                <span :if={is_nil(notification.read_at)} class="badge badge-error badge-xs">未读</span>
                <p class="ml-auto text-xs text-base-content/60">{format_time(notification.inserted_at)}</p>
              </div>
              <p class="font-medium">{notification.title}</p>
              <p :if={notification.body} class="whitespace-pre-line text-sm text-base-content/80">{notification.body}</p>
              <div :if={is_nil(notification.read_at)} class="card-actions justify-end">
                <button
                  class="btn btn-ghost btn-xs"
                  phx-click="mark-read"
                  phx-value-id={notification.id}
                >
                  标为已读
                </button>
              </div>
            </div>
          </div>

          <div :if={@notifications == []} class="mt-4 rounded-box bg-base-200/30 px-6 py-12 text-center">
            <.icon name="hero-bell-slash" class="size-8 text-base-content/40" />
            <p class="mt-2 text-sm text-base-content/60">暂无通知</p>
          </div>
        </div>
      </.student_shell>
    </Layouts.app>
    """
  end

  defp unread_count(notifications), do: Enum.count(notifications, &is_nil(&1.read_at))

  defp unread_text(0), do: "全部已读"
  defp unread_text(n), do: "#{n} 条未读"

  defp type_label(:system), do: "系统"
  defp type_label(:enrollment), do: "选课"
  defp type_label(:course_published), do: "课程发布"
  defp type_label(:progress), do: "学习进度"
  defp type_label(:quiz_graded), do: "答题"
  defp type_label(:ai_lesson), do: "AI 教学"
  defp type_label(_), do: "通知"

  defp type_badge(:system), do: "badge-info"
  defp type_badge(:enrollment), do: "badge-success"
  defp type_badge(:course_published), do: "badge-secondary"
  defp type_badge(:quiz_graded), do: "badge-warning"
  defp type_badge(_), do: "badge-ghost"

  defp format_time(nil), do: "-"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp load_notifications(socket) do
    student = socket.assigns.current_student

    notifications =
      try do
        Notification
        |> Ash.Query.for_read(:read, %{}, actor: student.actor, tenant: student.tenant)
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(50)
        |> Ash.read!()
      rescue
        _ -> []
      end

    assign(socket, :notifications, notifications)
  end
end
