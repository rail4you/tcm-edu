defmodule TcmEdu.Agents.QuizQuestionAction do
  @moduledoc """
  Jido Action：按主题生成结构化习题。

  由 `TcmEdu.Agents.QuizGenAgent` 挂载，供 `TcmEdu.Workers.QuizGenerationWorker`
  在 Oban 后台任务中直接调用（`run/2`），完成「LLM 生成 + 结构化数据验证」：

    1. 按中文医学出题 prompt 调 `TcmEdu.AI.Qwen`（qwen-flash）要求只返回 JSON 数组；
    2. 去 markdown 围栏 → `Jason.decode`；
    3. `TcmEdu.AI.QuizValidator.validate_items/2` 校验题型 / 题干 / 选项 / 答案，
       并归一化为可直接写入 `TcmEdu.Quiz.Question` 的属性。

  成功返回 `{:ok, %{questions: [question_attrs]}}`，失败返回
  `{:error, reason}`（Worker 据此把 QuizJob 置为 failed 并通知教师）。
  """

  use Jido.Action,
    name: "generate_structured_questions",
    description:
      "Generates structured quiz questions (single/multi/judge/essay) for a medical topic. " <>
        "Returns validated question attributes ready to persist.",
    schema:
      Zoi.object(%{
        topic: Zoi.string(),
        subject: Zoi.string() |> Zoi.optional(),
        count: Zoi.integer() |> Zoi.default(5),
        question_types: Zoi.list(Zoi.string()) |> Zoi.default(["single"]),
        difficulty: Zoi.integer() |> Zoi.default(3),
        knowledge_points: Zoi.list(Zoi.string()) |> Zoi.default([]),
        requirements: Zoi.string() |> Zoi.optional()
      })

  alias TcmEdu.AI.{Qwen, QuizValidator}

  require Logger

  @impl true
  def run(params, _context) do
    topic = Map.get(params, :topic, "") |> to_string() |> String.trim()
    subject = Map.get(params, :subject) || "中医"
    count = params |> Map.get(:count, 5) |> clamp_count()
    types = params |> Map.get(:question_types, ["single"]) |> normalize_types()
    difficulty = params |> Map.get(:difficulty, 3) |> clamp_difficulty()
    knowledge_points = Map.get(params, :knowledge_points, []) || []
    requirements = Map.get(params, :requirements)

    if topic == "" do
      {:error, "缺少出题主题（topic）"}
    else
      topic
      |> build_prompt(subject, count, types, difficulty, knowledge_points, requirements)
      |> request_llm()
      |> case do
        {:ok, raw} -> parse_and_validate(raw, count)
        {:error, _} = error -> error
      end
    end
  end

  # ── prompt ─────────────────────────────────────────────────

  defp build_prompt(topic, subject, count, types, difficulty, knowledge_points, requirements) do
    types_text = Enum.join(types, "、")

    """
    你是资深医学命题专家。请围绕以下主题生成 #{count} 道习题。
    - 学科：#{subject}
    - 主题：#{topic}
    - 题型（只能使用这些）：#{types_text}
    - 难度：#{difficulty}（1 最易，5 最难）
    #{if knowledge_points != [], do: "- 知识点侧重：#{Enum.join(knowledge_points, "、")}\n", else: ""}\
    #{if requirements not in [nil, ""], do: "- 补充要求：#{requirements}\n", else: ""}\
    只返回 JSON 数组，不要 markdown 围栏，不要解释。数组每项格式如下：

    [
      {
        "type": "single",
        "stem": "题干",
        "options": [
          {"label": "A", "text": "选项内容", "correct": true},
          {"label": "B", "text": "选项内容", "correct": false}
        ],
        "answer": "A",
        "explanation": "答案解析",
        "difficulty": #{difficulty},
        "knowledge_points": ["知识点"]
      }
    ]

    规则：
    - type 只能是 single（单选）/ multi（多选）/ judge（判断）/ essay（简答）之一；
    - single 必须有且仅有 1 个 correct=true 的选项；multi 至少 1 个；
    - judge 不需要 options，answer 只能是"对"或"错"；
    - essay 不需要 options，answer 写参考答案；
    - explanation 写 1-2 句解析；
    - 选项至少 2 个，文字不要带 A. B. 前缀。

    JSON：
    """
  end

  defp request_llm(prompt) do
    messages = [
      %{role: "system", content: "你只输出合法 JSON 数组。不要 markdown 围栏，不要解释。"},
      %{role: "user", content: prompt}
    ]

    case Qwen.chat(messages, temperature: 0.3, max_tokens: 8192) do
      {:ok, content} when is_binary(content) and content != "" -> {:ok, content}
      {:ok, _} -> {:error, "大模型返回了空内容"}
      {:error, reason} -> {:error, "大模型调用失败：#{format_reason(reason)}"}
    end
  end

  # ── parse + validate ───────────────────────────────────────

  defp parse_and_validate(raw, count) do
    raw
    |> strip_fences()
    |> Jason.decode()
    |> case do
      {:ok, data} ->
        case QuizValidator.validate_items(data, max_count: count) do
          {:ok, questions} ->
            Logger.info("[QuizQuestionAction] validated #{length(questions)} questions")
            {:ok, %{questions: questions}}

          {:error, reason} ->
            {:error, "AI 返回的数据校验失败：#{reason}"}
        end

      {:error, reason} ->
        {:error, "AI 返回的不是合法 JSON（#{inspect(reason)}）：#{String.slice(raw, 0, 120)}"}
    end
  end

  defp strip_fences(raw) do
    raw
    |> String.trim()
    |> String.replace(~r/^```(?:json)?\s*\n/, "")
    |> String.replace(~r/\n```\s*$/, "")
    |> String.trim()
  end

  # ── normalization ──────────────────────────────────────────

  defp clamp_count(n) when is_integer(n), do: n |> max(1) |> min(20)
  defp clamp_count(_), do: 5

  defp clamp_difficulty(n) when is_integer(n), do: n |> max(1) |> min(5)
  defp clamp_difficulty(_), do: 3

  defp normalize_types(types) when is_list(types) do
    valid = ~w(single multi judge essay)

    cleaned =
      types
      |> Enum.map(&(&1 |> to_string() |> String.trim() |> String.downcase()))
      |> Enum.filter(&(&1 in valid))
      |> Enum.uniq()

    if cleaned == [], do: ["single"], else: cleaned
  end

  defp normalize_types(_), do: ["single"]

  defp format_reason(:missing_key), do: "未配置大模型 Key"
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
