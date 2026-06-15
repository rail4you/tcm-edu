defmodule AshTsDemoWeb.ChatController do
  @moduledoc """
  Chat endpoint — uses AgentServer for multi-turn state,
  but runs ReAct directly for tool event visibility.
  """
  use AshTsDemoWeb, :controller

  require Ash.Query

  alias AshTsDemo.Chat.ChatMessage

  def options(conn, _params), do: send_resp(conn, 204, "")

  def chat(conn, params) do
    agent_name = params["agent_name"] || "chat_agent"
    sid = params["session_id"]
    msgs = params["messages"] || []
    user_msg = last_user_message(msgs)
    config = agent_config(agent_name)

    store_message(sid, "user", user_msg)

    # Build conversation history from DB
    history = load_history_maps(sid)

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    # Use ReAct.run directly for tool event visibility
    # Include history in the prompt for multi-turn context
    prompt = build_prompt(history, user_msg)

    result =
      Jido.AI.Reasoning.ReAct.run(prompt, %{
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

  # ─── agent configs ─────────────────────────────────────────

  defp agent_config("chat_agent") do
    %{model: :fast,
      system_prompt: "You are a helpful assistant with web access and math. Use web_fetch for URLs. Be concise.",
      tools: %{
        multiply: AshTsDemo.Agents.MultiplyAction,
        web_fetch: AshTsDemo.Agents.WebFetchAction
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

  defp agent_config(_), do: agent_config("chat_agent")

  # ─── helpers ───────────────────────────────────────────────

  defp last_user_message(msgs) do
    msgs
    |> Enum.filter(&(Map.get(&1, "role") == "user"))
    |> List.last()
    |> case do nil -> ""; m -> m["content"] || "" end
  end

  defp load_history_maps(sid) do
    ChatMessage
    |> Ash.Query.filter(session_id == ^sid)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!()
    |> Enum.map(fn m -> %{role: String.to_atom(m.role), content: m.content} end)
  rescue
    _ -> []
  end

  defp build_prompt(history, message) do
    if history == [] do
      message
    else
      context =
        history
        |> Enum.map(fn
          %{role: :user, content: c} -> "User: #{c}"
          %{role: :assistant, content: c} -> "Assistant: #{c}"
        end)
        |> Enum.join("\n")

      "Previous conversation:\n#{context}\n\nCurrent message: #{message}"
    end
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
