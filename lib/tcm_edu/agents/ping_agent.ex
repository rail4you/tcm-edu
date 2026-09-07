defmodule TcmEdu.Agents.PingAgent do
  @moduledoc """
  Agent "a" — can talk to other agents via the `call_agent` tool.

  The system prompt instructs the LLM to interpret `@<agent_name> <message>`
  patterns in user input as delegation requests: it must call
  `call_agent(agent_name, message)` and report the response back.
  """

  use Jido.AI.Agent,
    name: "ping_agent",
    description: "Calls other agents via the call_agent tool (the 'a' side of ping/pong).",
    tags: ["multi-agent", "orchestration"],
    model: :fast,
    tools: [
      TcmEdu.Agents.CallAgentAction
    ],
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
    """
end
