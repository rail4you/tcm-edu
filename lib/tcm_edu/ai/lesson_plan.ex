defmodule TcmEdu.AI.LessonPlan do
  @moduledoc """
  AI 备课助手（合同 §1.6.4 · 教师端 AI 教学准备）。

  基于 `TcmEdu.AI.Qwen`（qwen-flash）生成结构化医教教案：教学目标、重点难点、
  教学过程、板书、作业。参考 KnowledgeHub 的 chat 用法（system prompt + 结构化输出）。

  输出建议前端用 markdown 渲染，或后续解析为 JSON。
  """

  require Logger

  alias TcmEdu.AI.Qwen

  @system_prompt """
  你是资深医学教学设计专家。根据用户提供的章节/主题信息，生成结构化教案，包含以下部分：
  1. 教学目标（知识目标 / 能力目标 / 思政目标）
  2. 重点难点（重点 / 难点）
  3. 教学过程（导入 / 新课讲授 / 师生互动 / 巩固练习 / 小结）
  4. 板书设计
  5. 课后作业（含 2-3 道思考题）
  6. 建议课时与教法学法
  用 markdown 分节输出，简洁、可直接用于课堂。
  """

  @doc """
  生成教案。

  ## 参数

    * `topic`   — 章节/主题（必填）
    * `subject` — 学科（如 中医基础 / 解剖学 / 临床内科学）
    * `level`   — 学段（本科 / 规培 / 继续教育）
    * `audience`— 授课对象
  """
  @spec generate(keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate(opts \\ []) do
    topic = Keyword.get(opts, :topic)
    subject = Keyword.get(opts, :subject, "医学")
    level = Keyword.get(opts, :level, "本科")
    audience = Keyword.get(opts, :audience)

    user_content =
      """
      请为以下主题生成一份教案：
      - 主题：#{topic}
      - 学科：#{subject}
      - 学段：#{level}#{if audience, do: "\n- 授课对象：#{audience}"}
      """

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: String.trim(user_content)}
    ]

    case Qwen.chat(messages, opts) do
      {:ok, content} when is_binary(content) and content != "" ->
        {:ok, String.trim(content)}

      {:ok, _} ->
        {:error, :empty}

      {:error, reason} ->
        Logger.warning("[LessonPlan] generate failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
