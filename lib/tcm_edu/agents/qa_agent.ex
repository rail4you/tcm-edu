defmodule TcmEdu.Agents.QaAgent do
  @moduledoc """
  最普通的 AI 问答 Agent：无工具，纯对话。

  模型走 `Jido.AI` 的 `:qwen` 别名（`config/config.exs` 映射到
  ReqLLM `alibaba_cn:qwen-flash`，即 DashScope Qwen API）。
  会话历史由调用方（`TcmEdu.AI.QaChat` / LiveView）按会话从
  `chat_messages` 读出并传入，保证多轮连贯。
  """

  use Jido.AI.Agent,
    name: "qa_agent",
    model: :qwen,
    tools: [],
    system_prompt: """
    你是一位耐心的中医学习助手，用简洁的中文回答问题。
    回答要求：
    1. 直接回答用户当前问题，必要时结合上文历史保持连贯；
    2. 涉及经络腧穴、方剂、中药时给出准确名称， uncertain 时明确说明；
    3. 默认使用 Markdown，条理清晰，长度适中。
    """
end
