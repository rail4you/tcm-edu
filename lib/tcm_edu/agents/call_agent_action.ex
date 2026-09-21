defmodule TcmEdu.Agents.CallAgentAction do
  @moduledoc """
  Jido tool that delegates a message to another registered agent by name.

  The target agent's config (model, system prompt, tools) is looked up via
  `TcmEdu.Agents.Registry`. We then run a *synchronous* ReAct invocation
  against that config and return the final text answer.

  Use this when the current agent needs information from, or to forward a
  message to, another agent — for example, when the user writes
  `@pong_agent hello` in ping_agent's chat.
  """

  use Jido.Action,
    name: "call_agent",
    description: """
    Delegate a message to another agent by name. The target agent processes
    the message with its own system prompt and tools, and its response is
    returned as the tool's output.

    Use this when the user @-mentions another agent or asks you to talk to
    another agent.
    """,
    schema:
      Zoi.object(%{
        agent_name:
          Zoi.string(
            description:
              "Name of the target agent. One of: pong_agent, ping_agent, chat_agent, " <>
                "bg_task_agent, counter_agent, quiz_agent."
          ),
        message: Zoi.string(description: "Message to send to the target agent.")
      })

  require Logger

  alias TcmEdu.Agents.Registry

  @impl true
  def run(params, _context) do
    case Registry.config(params.agent_name) do
      nil ->
        known = Enum.join(Registry.names(), ", ")
        {:error, "Unknown agent: #{params.agent_name}. Known agents: #{known}"}

      config ->
        # Synchronous, non-streaming ReAct run for the target agent.
        # The target gets its own system prompt + tools, so the call is
        # essentially "treat me as a fresh user and answer this message".
        result =
          Jido.AI.Reasoning.ReAct.run(params.message, %{
            model: config.model,
            system_prompt: config.system_prompt,
            tools: config.tools,
            streaming: false,
            max_iterations: config[:max_iterations] || 3
          })

        answer = Map.get(result, :result) || Map.get(result, :answer) || ""

        Logger.info(
          "call_agent: #{params.agent_name} → #{String.slice(to_string(answer), 0, 100)}"
        )

        {:ok, %{agent_name: params.agent_name, response: to_string(answer)}}
    end
  end
end
