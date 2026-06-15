defmodule AshTsDemo.Workers.LongTaskWorker do
  @moduledoc """
  Oban worker that simulates a long-running task (default 15 s).

  The work is intentionally a `Process.sleep/1` mock so we can exercise the
  end-to-end flow (tool call → queued job → status updates → chat message)
  without real CPU-bound work.

  On every state change the worker:

    1. Updates the matching `ChatTask` row (`mark_running`, `mark_completed` or
       `mark_failed`).
    2. Broadcasts a `Phoenix.PubSub` event to `chat:user:<id>:tasks` so
       the SSE notifications endpoint can forward it to the open chat tab.
    3. On success, persists an assistant chat message into the same session so
       the user sees the completion when they reload the conversation.

  The controller pre-creates the `ChatTask` row with status `:pending` and
  broadcasts the initial `:task_started` event, so the worker simply looks the
  row up and continues from `:running`.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 60, keys: [:task_id]]

  alias AshTsDemo.Chat.{ChatMessage, ChatTask}
  require Ash.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "task_id" => _task_id,
      "user_id" => user_id,
      "session_id" => _session_id,
      "task_name" => _task_name,
      "duration_ms" => duration_ms
    } = args

    topic = "chat:user:#{user_id}:tasks"

    with {:ok, %ChatTask{} = chat_task} <- fetch_or_create_chat_task(args) do
      run_task(chat_task, topic, duration_ms)
    end
  end

  # ── helpers ────────────────────────────────────────────────

  # The controller normally pre-creates the row. If we still don't find it
  # (e.g. job was retried manually, or unique conflict resolution raced) we
  # create one on the fly so the worker never silently no-ops.
  defp fetch_or_create_chat_task(args) do
    case Ash.Query.filter(ChatTask, task_id == ^args["task_id"]) |> Ash.read_one() do
      {:ok, %ChatTask{} = task} ->
        {:ok, task}

      _ ->
        Ash.Changeset.for_create(ChatTask, :create, %{
          task_id: args["task_id"],
          user_id: args["user_id"],
          session_id: args["session_id"],
          agent_name: args["agent_name"] || "chat_agent",
          task_name: args["task_name"],
          duration_ms: args["duration_ms"],
          status: :pending
        })
        |> Ash.create()
    end
  end

  defp run_task(%ChatTask{} = chat_task, topic, duration_ms) do
    with {:ok, running_task} <- mark_status(chat_task, :mark_running) do
      broadcast_event(topic, :task_running, chat_task_payload(running_task))

      Process.sleep(duration_ms)

      result = %{
        task_id: running_task.task_id,
        task_name: running_task.task_name,
        completed_at: DateTime.utc_now(),
        duration_ms: duration_ms
      }

      {:ok, completed_task} =
        Ash.Changeset.for_update(running_task, :mark_completed, %{result: result})
        |> Ash.update()

      broadcast_event(topic, :task_completed, chat_task_payload(completed_task))
      append_assistant_message(running_task.session_id, running_task.task_id, running_task.task_name, duration_ms)

      :ok
    else
      {:error, reason} ->
        fail_task(chat_task, reason, topic)
    end
  end

  defp mark_status(%ChatTask{} = task, action) do
    Ash.Changeset.for_update(task, action) |> Ash.update()
  end

  defp fail_task(%ChatTask{} = task, reason, topic) do
    message =
      case reason do
        %Ash.Changeset{} = cs -> inspect(cs.errors)
        other -> inspect(other)
      end

    case Ash.Changeset.for_update(task, :mark_failed, %{error_message: message}) |> Ash.update() do
      {:ok, failed} ->
        broadcast_event(topic, :task_failed, chat_task_payload(failed))
        :ok

      _ ->
        :ok
    end
  end

  defp append_assistant_message(session_id, task_id, task_name, duration_ms) do
    seconds = div(duration_ms, 1000)

    ChatMessage
    |> Ash.Changeset.for_create(:create, %{
      session_id: session_id,
      role: "assistant",
      content:
        "后台任务完成通知：任务 `#{task_name}`（ID `#{task_id}`）已成功执行，" <>
          "耗时 #{seconds} 秒。你可以继续聊天，我会在这里等你。"
    })
    |> Ash.create()

    :ok
  rescue
    _ -> :ok
  end

  defp chat_task_payload(%ChatTask{} = task) do
    %{
      task_id: task.task_id,
      task_name: task.task_name,
      status: task.status,
      session_id: task.session_id,
      job_id: task.job_id,
      duration_ms: task.duration_ms,
      inserted_at: task.inserted_at,
      started_at: task.started_at,
      completed_at: task.completed_at
    }
  end

  defp broadcast_event(topic, type, payload) do
    Phoenix.PubSub.broadcast(AshTsDemo.PubSub, topic, {:task_event, type, payload})
  rescue
    _ -> :ok
  end
end
