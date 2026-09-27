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
    if connected?(socket) and socket.assigns.current_student do
      student = socket.assigns.current_student
      Phoenix.PubSub.subscribe(TcmEdu.PubSub, "notifications:#{student.tenant}:#{student.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, "通知中心")
     |> load_notifications()}
  end

  @impl true
  def handle_info({:exam_graded, %{exam_name: exam_name}}, socket) do
    {:noreply,
     socket
     |> load_notifications()
     |> put_flash(:info, "收到新通知：试卷《#{exam_name}》已批改")}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

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

  defp unread_count(notifications), do: Enum.count(notifications, &is_nil(&1.read_at))

  defp unread_text(0), do: "全部已读"
  defp unread_text(n), do: "#{n} 条未读"

  defp type_label(:system), do: "系统"
  defp type_label(:enrollment), do: "选课"
  defp type_label(:course_published), do: "课程发布"
  defp type_label(:progress), do: "学习进度"
  defp type_label(:quiz_graded), do: "答题"
  defp type_label(:exam_graded), do: "考试批改"
  defp type_label(:exam_assigned), do: "考试分配"
  defp type_label(:ai_lesson), do: "AI 教学"
  defp type_label(_), do: "通知"

  defp type_badge(:system), do: "badge-info"
  defp type_badge(:enrollment), do: "badge-success"
  defp type_badge(:course_published), do: "badge-secondary"
  defp type_badge(:quiz_graded), do: "badge-warning"
  defp type_badge(:exam_graded), do: "badge-success"
  defp type_badge(:exam_assigned), do: "badge-info"
  defp type_badge(_), do: "badge-ghost"

  defp format_time(nil), do: "-"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp notification_route(%{payload: %{"route" => route}}) when is_binary(route), do: route
  defp notification_route(%{payload: %{route: route}}) when is_binary(route), do: route
  defp notification_route(_), do: nil

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
