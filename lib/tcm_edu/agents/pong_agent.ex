defmodule TcmEdu.Agents.PongAgent do
  @moduledoc """
  Agent "b" — always replies with the single word "pong". No tools.

  This is the canonical "echo server" used together with `PingAgent` to
  demonstrate inter-agent delegation: ping_agent calls call_agent with
  agent_name="pong_agent", and the response is always `pong`.
  """

  use Jido.AI.Agent,
    name: "pong_agent",
    description: "Always replies 'pong' to any message.",
    tags: ["echo", "demo"],
    model: :fast,
    tools: [],
    system_prompt: """
    You are pong_agent (b). Your only response — to any message from any
    user or any other agent — is the single word: pong.

    Do not call any tools. Do not elaborate. Do not explain. Just reply
    with the word `pong`.
    """
end
