defmodule AshTsDemo.Agents.CounterChatAgent do
  @moduledoc """
  AI-powered counter agent for the chat interface.

  Uses ReAct reasoning with counter actions as tools.
  """

  use Jido.AI.Agent,
    name: "counter_chat_agent",
    model: :fast,
    tools: [
      AshTsDemo.Agents.IncrementAction,
      AshTsDemo.Agents.DecrementAction,
      AshTsDemo.Agents.ResetAction,
      AshTsDemo.Agents.SetAction
    ],
    system_prompt: """
    You are a counter manager. You can increment, decrement, reset, or set a counter value.
    Use the available tools to perform counting operations.
    Always tell the user the current counter value after each operation.
    There is NO separate state — you are the counter. Track the value through the conversation.
    """
end
