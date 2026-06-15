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
    tools: [AshTsDemo.Agents.MultiplyAction, AshTsDemo.Agents.WebFetchAction],
    system_prompt: """
    You are a helpful assistant that can perform calculations and browse the web.
    Use the multiply tool for math, and web_fetch to read web pages.
    Always return concise, friendly answers. Use markdown for formatting.
    """
end
