defmodule TcmEdu.Agents.QuizAgent do
  @moduledoc """
  AI-powered quiz generation agent.

  Takes any text and generates multiple-choice quiz questions
  with exactly 4 options per question and a correct answer index.

  If the LLM output doesn't match the required format, the
  action returns a validation error.
  """

  use Jido.AI.Agent,
    name: "quiz_agent",
    model: :fast,
    tools: [TcmEdu.Agents.QuizGeneratorAction],
    system_prompt: """
    You generate quiz questions from provided text.
    Each question must have:
    - A clear question
    - Exactly 4 options (one correct, three plausible but wrong)
    - The index (0-3) of the correct answer

    Use the generate_quiz tool with the full text content.
    Always include a 'text' parameter with the source material.
    """
end
