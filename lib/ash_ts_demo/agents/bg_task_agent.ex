defmodule AshTsDemo.Agents.BgTaskAgent do
  @moduledoc """
  Minimal, focused agent whose ONLY tool is `start_long_task`.

  Why a separate agent? The general `chat_agent` accumulates a lot of
  conversation history over time and the small `:fast` model tends to
  "hallucinate" a tool result (write "task started" in plain text) instead
  of actually invoking the tool when the context is very long.

  This agent has:
    * a single tool (`start_long_task`) — nothing else to confuse the model
    * a short, directive system prompt that forbids describing task state
      in plain text without first calling the tool
    * its own session id (`chat_session_bg_task_agent`), so users get a
      clean context every time they switch to it
  """

  use Jido.AI.Agent,
    name: "bg_task_agent",
    model: :fast,
    tools: [
      AshTsDemo.Agents.LongTaskAction
    ],
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
    """
end
