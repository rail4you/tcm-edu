defmodule AshTsDemo.Agents.ChatAgent do
  @moduledoc """
  An AI-powered agent backed by a language model.

  Uses the ReAct (Reasoning + Acting) strategy:
  - The model reasons about the user's request
  - Calls tools (like multiply) when needed
  - Returns a final answer

  Model: `:fast` → via jido_ai model_aliases
  Tools: MultiplyAction
  """

  use Jido.AI.Agent,
    name: "chat_agent",
    model: :fast,
    tools: [AshTsDemo.Agents.MultiplyAction],
    system_prompt: """
    You are a helpful assistant that can perform calculations.
    Use the multiply tool for any multiplication requests.
    Always return a concise, friendly answer in plain text.
    """
end
