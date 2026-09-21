defmodule TcmEdu.Agents.Registry do
  @moduledoc """
  Central registry mapping `agent_name` → runtime config.

  Used by:

    * `TcmEduWeb.ChatController` to look up the config for the
      currently-selected agent.
    * `TcmEdu.Agents.CallAgentAction` (the tool) to invoke any
      other registered agent.

  Adding a new agent: write a `defp xxx_agent/0` clause here, add it
  to the `config/1` dispatch, and (optionally) add the module under
  `lib/tcm_edu/agents/`.
  """

  alias TcmEdu.Agents.{
    CallAgentAction,
    DecrementAction,
    IncrementAction,
    LongTaskAction,
    MultiplyAction,
    QuizGeneratorAction,
    ResetAction,
    SetAction,
    WebFetchAction
  }

  @type config :: %{
          required(:model) => atom(),
          required(:system_prompt) => String.t(),
          required(:tools) => %{optional(String.t()) => module()},
          optional(:max_iterations) => pos_integer()
        }

  @spec config(String.t()) :: config() | nil
  def config(agent_name) when is_binary(agent_name) do
    case agent_name do
      "chat_agent" -> chat_agent()
      "counter_agent" -> counter_agent()
      "quiz_agent" -> quiz_agent()
      "bg_task_agent" -> bg_task_agent()
      "ping_agent" -> ping_agent()
      "pong_agent" -> pong_agent()
      _ -> nil
    end
  end

  @spec names() :: [String.t()]
  def names, do: ~w(chat_agent counter_agent quiz_agent bg_task_agent ping_agent pong_agent)

  @spec fallback() :: config()
  def fallback, do: chat_agent()

  # ─── agents ──────────────────────────────────────────────────

  defp chat_agent do
    %{
      model: :fast,
      system_prompt: """
      You are a helpful assistant that can perform calculations, browse the web, and
      run background tasks. Use the multiply tool for math, web_fetch to read web pages,
      and start_long_task whenever the user wants to run something heavy in the
      background. Always return concise, friendly answers in markdown.
      """,
      tools: %{
        multiply: MultiplyAction,
        web_fetch: WebFetchAction,
        start_long_task: LongTaskAction
      },
      max_iterations: 5
    }
  end

  defp counter_agent do
    %{
      model: :fast,
      system_prompt: "You are a counter manager. Use the tools provided.",
      tools: %{
        increment: IncrementAction,
        decrement: DecrementAction,
        reset: ResetAction,
        set: SetAction
      },
      max_iterations: 5
    }
  end

  defp quiz_agent do
    %{
      model: :fast,
      system_prompt:
        "You generate quiz questions. Use markdown. If tool fails, explain the error.",
      tools: %{generate_quiz: QuizGeneratorAction},
      max_iterations: 5
    }
  end

  defp bg_task_agent do
    %{
      model: :fast,
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
      tools: %{start_long_task: LongTaskAction},
      max_iterations: 5
    }
  end

  # ── ping / pong pair (a ↔ b) ───────────────────────────────────

  # Agent "a". Holds the `call_agent` tool, so it can forward messages to
  # any registered agent by name. When the user writes `@<agent> <msg>` in
  # chat, this agent is expected to parse that and dispatch via call_agent.
  defp ping_agent do
    %{
      model: :fast,
      system_prompt: """
      You are ping_agent (a). You can talk to any other agent by calling the
      `call_agent` tool.

      Strict pattern when the user writes `@<agent_name> <message>` in chat:
        1. Call call_agent(agent_name="<agent_name>", message="<message>").
        2. Read the response field of the tool result.
        3. Reply in plain language, e.g. "<agent_name> replied: pong".

      Known agents: pong_agent (always replies "pong"), chat_agent,
      bg_task_agent, counter_agent, quiz_agent. If unsure which to call, ask.

      For free-form delegation ("ask X to do Y"), call call_agent with the
      appropriate agent_name and the rest of the message.

      NEVER invent a tool result. If you need information from another agent,
      you MUST use call_agent.
      """,
      tools: %{call_agent: CallAgentAction},
      max_iterations: 5
    }
  end

  # Agent "b". No tools. Always replies with the single word "pong".
  defp pong_agent do
    %{
      model: :fast,
      system_prompt: """
      You are pong_agent (b). Your only response — to any message from any
      user or any other agent — is the single word: pong.

      Do not call any tools. Do not elaborate. Do not explain. Just reply
      with the word `pong`.
      """,
      tools: %{},
      max_iterations: 1
    }
  end
end
