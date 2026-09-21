defmodule TcmEdu.Agents.LongTaskAction do
  @moduledoc """
  Jido tool that lets the chat agent kick off a long-running background task.

  The tool itself does NOT do the work — it just mints a `task_id` and returns
  it immediately so the LLM response is never blocked.

  The chat controller inspects the `:tool_completed` trace event for this
  action and inserts the matching Oban job (`TcmEdu.Workers.LongTaskWorker`)
  plus the `ChatTask` row that the worker uses to stream status back to the
  browser.
  """

  use Jido.Action,
    name: "start_long_task",
    description:
      "Start a long-running background task (e.g. heavy computation, batch import, " <>
        "report generation). Returns immediately with a task_id so the user can " <>
        "keep chatting. The user will be notified in the chat when the task finishes. " <>
        "Use this whenever the user asks to 'kick off', 'start', 'run in the background', " <>
        "'long task', 'async job', or anything that implies processing will take more " <>
        "than a few seconds.",
    schema:
      Zoi.object(%{
        task_name:
          Zoi.string(
            description:
              "Short human-readable label for the task, used in the notification banner."
          ),
        duration_ms:
          Zoi.integer(
            description:
              "How long the simulated work should take in milliseconds (default 15000)."
          )
          |> Zoi.default(15_000)
      })

  @impl true
  def run(params, _context) do
    task_id = Ecto.UUID.generate()

    {:ok,
     %{
       task_id: task_id,
       task_name: params.task_name,
       duration_ms: params.duration_ms,
       status: "queued",
       message:
         "Task \"#{params.task_name}\" queued. You can keep chatting — I'll post a " <>
           "message here as soon as it finishes."
     }}
  end
end
