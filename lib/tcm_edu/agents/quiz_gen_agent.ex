defmodule TcmEdu.Agents.QuizGenAgent do
  @moduledoc """
  AI 出题 Agent：挂载 `generate_structured_questions` 工具。

  教师在 `/teacher/ai/quiz` 提交的需求由 Oban Worker 直接调用该 Agent 的
  Action（`TcmEdu.Agents.QuizQuestionAction.run/2`）完成生成与结构化验证；
  在聊天场景下也可经由 `TcmEdu.Agents.Registry`（`"quiz_gen_agent"`）用
  ReAct 方式编排调用。
  """

  use Jido.AI.Agent,
    name: "quiz_gen_agent",
    model: :qwen,
    tools: [TcmEdu.Agents.QuizQuestionAction],
    system_prompt: """
    你是资深医学命题专家。根据用户给出的主题、题型、难度生成结构化习题。
    必须调用 generate_structured_questions 工具完成出题，不要自己编造题目文本。
    工具返回后，用 1-2 句中文总结生成结果（数量、题型构成）。
    """
end
