defmodule AshTsDemo.Agents.ChatAgent do
  @moduledoc """
  An AI-powered agent backed by a language model.

  Uses the ReAct (Reasoning + Acting) strategy:
  - The model reasons about the user's request
  - Calls tools (like multiply) when needed
  - Returns a final answer

  Model: `:fast` → via jido_ai model_aliases
  Tools: MultiplyAction, WebFetchAction, LongTaskAction
  """

  use Jido.AI.Agent,
    name: "chat_agent",
    model: :fast,
    tools: [
      AshTsDemo.Agents.MultiplyAction,
      AshTsDemo.Agents.WebFetchAction,
      AshTsDemo.Agents.LongTaskAction
    ],
    system_prompt: """
    You are a helpful assistant that can perform calculations, browse the web, and
    run background tasks. Use the multiply tool for math, web_fetch to read web pages,
    and start_long_task whenever the user wants to run something heavy in the
    background. Always return concise, friendly answers in markdown.
    """
end
