defmodule AshTsDemoWeb.ChatController do
  @moduledoc """
  Chat endpoint — uses AgentServer for multi-turn state,
  but runs ReAct directly for tool event visibility.
  """
  use AshTsDemoWeb, :controller

  require Ash.Query

  alias AshTsDemo.Chat.ChatMessage
  alias AshTsDemo.Workers.LongTaskWorker

  def options(conn, _params), do: send_resp(conn, 204, "")

  def chat(conn, params) do
    agent_name = params["agent_name"] || "chat_agent"
    sid = params["session_id"]
    msgs = params["messages"] || []
    user_msg = last_user_message(msgs)
    config = agent_config(agent_name)

    user = conn.assigns[:current_user]
    user_id = user && user.id

    store_message(sid, "user", user_msg)

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    # Use ReAct.run directly for tool event visibility.
    # We only pass the *current* user message — conversation history is owned
    # by the client (browser) and persisted in `chat_messages` for display
    # purposes, but never concatenated into the prompt. This keeps each turn
    # focused and prevents long-context hallucinations.
    result =
      Jido.AI.Reasoning.ReAct.run(user_msg, %{
        model: config.model,
        system_prompt: config.system_prompt,
        tools: config.tools,
        streaming: true,
        max_iterations: 5
      })

    answer = Map.get(result, :result) || Map.get(result, :answer) || ""

    # Send tool calls from trace
    trace = result[:trace] || []
    tool_events =
      Enum.filter(trace, fn e -> e.kind in [:tool_started, :tool_completed] end)

    for event <- tool_events do
      case event.kind do
        :tool_started ->
          data = Jason.encode!(%{
            type: "tool-call",
            toolCallId: event.tool_call_id || "",
            toolName: event.tool_name || "",
            args: event.data[:arguments] || event.data
          })
          _ = Plug.Conn.chunk(conn, "8:#{data}\n")

        :tool_completed ->
          maybe_enqueue_long_task(event, agent_name, sid, user_id)

          data = Jason.encode!(%{
            type: "tool-result",
            toolCallId: event.tool_call_id || "",
            toolName: event.tool_name || "",
            result: format_tool_output(event.data)
          })
          _ = Plug.Conn.chunk(conn, "8:#{data}\n")

        _ -> :ok
      end
    end

    # Stream answer character by character
    answer
    |> String.graphemes()
    |> Enum.each(fn c ->
      data = Jason.encode!(%{type: "text-delta", textDelta: c})
      _ = Plug.Conn.chunk(conn, "0:#{data}\n")
      Process.sleep(10)
    end)

    store_message(sid, "assistant", answer)
    _ = Plug.Conn.chunk(conn, "d:{\"finishReason\":\"stop\"}\n")
    conn
  rescue
    e ->
      _ = Plug.Conn.chunk(conn, "3:#{Jason.encode!(inspect(Exception.message(e)))}\n")
      _ = Plug.Conn.chunk(conn, "d:{\"finishReason\":\"error\"}\n")
      conn
  end

  # ─── background task plumbing ──────────────────────────────

  # When the `start_long_task` tool completes, queue an Oban job so the work
  # happens off the request thread. The tool returns a `task_id` already, so we
  # reuse it when constructing the worker args.
  defp maybe_enqueue_long_task(%{kind: :tool_completed, tool_name: "start_long_task"} = event,
                              agent_name,
                              session_id,
                              user_id) do
    result = extract_tool_result(event.data)
    task_id = result[:task_id]
    task_name = result[:task_name]
    duration_ms = result[:duration_ms]

    cond do
      is_nil(task_id) or is_nil(task_name) ->
        :skip

      is_nil(user_id) ->
        # No authenticated user → can't broadcast / persist a chat_task.
        # Log and skip so the chat still works for anonymous demos.
        require Logger
        Logger.warning("start_long_task: missing user_id, skipping enqueue")

      true ->
        # Pre-create the ChatTask row so the SSE endpoint can show the
        # indicator immediately, even if the Oban worker is briefly delayed
        # in picking the job up. Worker will look it up by task_id and
        # update it.
        _ =
          Ash.Changeset.for_create(AshTsDemo.Chat.ChatTask, :create, %{
            task_id: task_id,
            user_id: user_id,
            session_id: session_id,
            agent_name: agent_name,
            task_name: task_name,
            duration_ms: duration_ms || 15_000,
            status: :pending
          })
          |> Ash.create()

        {:ok, job} =
          LongTaskWorker.new(%{
            "task_id" => task_id,
            "user_id" => user_id,
            "session_id" => session_id,
            "agent_name" => agent_name,
            "task_name" => task_name,
            "duration_ms" => duration_ms || 15_000
          })
          |> Oban.insert()

        require Logger
        Logger.info("start_long_task: enqueued job=#{job.id} task_id=#{task_id}")

        broadcast_task_event(user_id, :task_started, %{
          task_id: task_id,
          task_name: task_name,
          status: "pending",
          session_id: session_id,
          job_id: job.id,
          duration_ms: duration_ms || 15_000
        })

        :ok
    end
  end

  defp maybe_enqueue_long_task(_event, _agent_name, _session_id, _user_id) do
    require Logger
    kind = if is_map(_event), do: Map.get(_event, :kind) || Map.get(_event, :tool_name), else: nil
    tool_name = if is_map(_event), do: Map.get(_event, :tool_name), else: nil
    Logger.info("DBG: maybe_enqueue_long_task FELL THROUGH kind=#{inspect(kind)} tool_name=#{inspect(tool_name)}")
    :ok
  end

  defp broadcast_task_event(user_id, type, payload) do
    Phoenix.PubSub.broadcast(
      AshTsDemo.PubSub,
      "chat:user:#{user_id}:tasks",
      {:task_event, type, payload}
    )
  rescue
    _ -> :ok
  end

  # The trace event data can be shaped in a few ways depending on the Jido
  # version. Normalise to a map of atoms so we can pluck out fields.
  # Note: Jido 2.x emits 3-tuples `{:ok, data, metadata}` on tool completion,
  # so the 3-tuple clause MUST come first (3-tuple is a 2-tuple as well and
  # would otherwise match the 2-tuple clause with `data = {meta}`).
  defp extract_tool_result(%{result: {:ok, %{} = data, _meta}}), do: data
  defp extract_tool_result(%{result: {:ok, %{} = data}}), do: data
  defp extract_tool_result(%{result: {:ok, data}}) when is_map(data), do: data
  defp extract_tool_result(%{result: %{} = data}), do: data
  defp extract_tool_result(%{"result" => %{} = data}), do: data
  defp extract_tool_result(_), do: %{}

  # ─── agent configs ─────────────────────────────────────────

  defp agent_config("chat_agent") do
    %{model: :fast,
      system_prompt: """
      You are a helpful assistant with web access, math, and background tasks.
      Use web_fetch for URLs, multiply for math, and start_long_task whenever
      the user wants to run something heavy in the background. Be concise.
      """,
      tools: %{
        multiply: AshTsDemo.Agents.MultiplyAction,
        web_fetch: AshTsDemo.Agents.WebFetchAction,
        start_long_task: AshTsDemo.Agents.LongTaskAction
      }}
  end

  defp agent_config("counter_agent") do
    %{model: :fast,
      system_prompt: "You are a counter manager. Use the tools provided.",
      tools: %{
        increment: AshTsDemo.Agents.IncrementAction,
        decrement: AshTsDemo.Agents.DecrementAction,
        reset: AshTsDemo.Agents.ResetAction,
        set: AshTsDemo.Agents.SetAction
      }}
  end

  defp agent_config("quiz_agent") do
    %{model: :fast,
      system_prompt: "You generate quiz questions. Use markdown. If tool fails, explain the error.",
      tools: %{generate_quiz: AshTsDemo.Agents.QuizGeneratorAction}}
  end

  # Minimal agent whose only tool is start_long_task. Useful for testing the
  # background-task pipeline without the noise / context bloat of chat_agent.
  defp agent_config("bg_task_agent") do
    %{model: :fast,
      system_prompt: """
      You are a background task assistant. Your only job is to call the
      `start_long_task` tool when the user asks for a background / async /
      long-running / heavy job.

      STRICT RULES:
      1. Whenever the user wants a background task, you MUST invoke the
         `start_long_task` tool. Plain text like "the task is started" is NOT
         acceptable — the tool call is the only thing that actually starts a
         task and produces the badge / completion notification in the UI.
      2. After the tool returns, write a 1-2 sentence confirmation in Chinese
         that includes the task name and the expected duration.
      3. Do not use any other tools. If the user asks for math / web fetch /
         jokes, politely say this agent only handles background tasks.

      Tool parameters:
        - task_name (required): short label shown in the UI banner
        - duration_ms (optional, default 15000): simulated work duration in ms
          → pass a smaller value (e.g. 3000) when the user says "3 秒"
      """,
      tools: %{
        start_long_task: AshTsDemo.Agents.LongTaskAction
      }}
  end

  defp agent_config(_), do: agent_config("chat_agent")

  # ─── helpers ───────────────────────────────────────────────

  defp last_user_message(msgs) do
    msgs
    |> Enum.filter(&(Map.get(&1, "role") == "user"))
    |> List.last()
    |> case do nil -> ""; m -> m["content"] || "" end
  end

  defp format_tool_output(%{result: {:ok, data, _}}), do: inspect(data)
  defp format_tool_output(%{result: {:ok, data}}), do: inspect(data)
  defp format_tool_output(%{result: data}), do: inspect(data)
  defp format_tool_output(%{"result" => data}), do: inspect(data)
  defp format_tool_output(data), do: inspect(data)

  defp store_message(sid, role, content) do
    ChatMessage
    |> Ash.Changeset.for_create(:create, %{session_id: sid, role: role, content: content})
    |> Ash.create()
  rescue
    _ -> :ok
  end
end
