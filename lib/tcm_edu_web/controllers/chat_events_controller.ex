defmodule TcmEduWeb.ChatEventsController do
  @moduledoc """
  SSE endpoint that streams long-running-task lifecycle events to the
  currently-open chat tab.

  Wire format (one event per message, terminated by a blank line):

      event: task-list
      data: {"tasks":[{...}]}

      event: task-started
      data: {"task_id":"...","task_name":"...", ...}

  On connect the controller sends a `task-list` event containing every still
  in-flight task for the user so a refresh / tab-switch can recover the
  indicator without losing state. Subsequent state changes are streamed as
  individual `task-started`, `task-running`, `task-completed`, `task-failed`
  events.
  """

  use TcmEduWeb, :controller

  alias TcmEdu.Chat.ChatTask
  require Ash.Query

  @heartbeat_ms 15_000

  def subscribe(conn, _params) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        send_resp(conn, 401, Jason.encode!(%{error: "unauthorized"}))

      true ->
        user_id = user.id
        topic = "chat:user:#{user_id}:tasks"

        Phoenix.PubSub.subscribe(TcmEdu.PubSub, topic)

        conn =
          conn
          |> put_resp_content_type("text/event-stream")
          |> put_resp_header("cache-control", "no-cache")
          |> put_resp_header("x-accel-buffering", "no")
          |> put_resp_header("connection", "keep-alive")
          |> send_chunked(200)

        # Initial snapshot of all still-running tasks so a tab reload can
        # rebuild the indicator without losing state.
        send_event(conn, "task-list", %{tasks: active_tasks(user_id)})

        stream_loop(conn, topic)
    end
  end

  # ── stream loop ────────────────────────────────────────────

  defp stream_loop(conn, topic) do
    receive do
      {:task_event, type, payload} ->
        send_event(conn, Atom.to_string(type), payload)
        stream_loop(conn, topic)

      {:tcp_closed, _sock} ->
        :ok

      {:tcp_error, _sock, _reason} ->
        :ok

      other ->
        # Ignore unknown messages, but keep listening.
        _ = other
        stream_loop(conn, topic)
    after
      @heartbeat_ms ->
        _ = Plug.Conn.chunk(conn, ": heartbeat\n\n")
        stream_loop(conn, topic)
    end
  end

  defp send_event(conn, type, payload) do
    data = Jason.encode!(payload)
    _ = Plug.Conn.chunk(conn, "event: #{type}\ndata: #{data}\n\n")
  end

  # ── helpers ────────────────────────────────────────────────

  defp active_tasks(user_id) do
    ChatTask
    |> Ash.Query.filter(user_id == ^user_id and status in [:pending, :running])
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!()
    |> Enum.map(&serialize/1)
  rescue
    _ -> []
  end

  defp serialize(%ChatTask{} = t) do
    %{
      task_id: t.task_id,
      task_name: t.task_name,
      status: t.status,
      session_id: t.session_id,
      job_id: t.job_id,
      duration_ms: t.duration_ms,
      inserted_at: t.inserted_at,
      started_at: t.started_at,
      completed_at: t.completed_at
    }
  end
end
