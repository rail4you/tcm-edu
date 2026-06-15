defmodule AshTsDemoWeb.ChatController do
  @moduledoc """
  Chat streaming endpoint.

  POST /api/chat
    { "agent_name": "...", "session_id": "...", "messages": [...] }
  """
  use AshTsDemoWeb, :controller

  require Ash.Query

  alias AshTsDemo.Chat.ChatMessage

  def options(conn, _params), do: send_resp(conn, 204, "")

  def chat(conn, params) do
    agent = params["agent_name"] || "chat_agent"
    sid = params["session_id"]
    msgs = params["messages"] || []
    user_msg = last_user_message(msgs)
    config = agent_config(agent)

    store_message(sid, "user", user_msg)

    conn = conn
    |> put_resp_content_type("text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("x-accel-buffering", "no")
    |> send_chunked(200)

    result = Jido.AI.Reasoning.ReAct.run(user_msg, %{
      model: config.model,
      system_prompt: config.system_prompt,
      tools: config.tools,
      messages: load_history_maps(sid),
      streaming: true,
      max_iterations: 5
    })

    answer = Map.get(result, :result) || Map.get(result, :answer) || ""

    # Stream character by character for smooth typing effect
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

  defp agent_config("chat_agent") do
    %{
      model: :fast,
      system_prompt: "You are a helpful assistant. Use markdown for formatting: code blocks with ```python, math with $...$ or $$...$$, tables, lists. Be concise.",
      tools: %{}
    }
  end

  defp agent_config("counter_agent") do
    %{
      model: :fast,
      system_prompt: "You are a counter manager. Use the tools provided.",
      tools: %{
        increment: AshTsDemo.Agents.IncrementAction,
        decrement: AshTsDemo.Agents.DecrementAction,
        reset: AshTsDemo.Agents.ResetAction,
        set: AshTsDemo.Agents.SetAction
      }
    }
  end

  defp agent_config(_), do: agent_config("chat_agent")

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

  defp store_message(sid, role, content) do
    ChatMessage
    |> Ash.Changeset.for_create(:create, %{session_id: sid, role: role, content: content})
    |> Ash.create()
  rescue
    _ -> :ok
  end
end
