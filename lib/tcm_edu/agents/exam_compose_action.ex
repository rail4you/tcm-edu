defmodule TcmEdu.Agents.ExamComposeAction do
  @moduledoc """
  Jido Action：从题库候选题目里「智能组卷」——挑选题目组成一份试卷。

  由 `TcmEdu.Workers.ExamGenerationWorker` 在 Oban 后台任务中调用（`run/2`）：

    1. 先做一次**确定性兜底**（`TcmEdu.AI.ExamComposer.select/2`），
       保证大模型不可用时组卷仍能完成；
    2. 尝试调 `TcmEdu.AI.Qwen`（qwen-flash）让大模型按主题/知识点从候选里挑题，
       返回 `{"question_ids": [...]}`；
    3. 用 `TcmEdu.AI.ExamComposer.validate/3` 校验大模型选中的 id：
       合法 → 采用大模型结果；非法/失败 → 回退到兜底结果。

  成功返回 `{:ok, %{question_ids: [String.t()]}}`，失败返回 `{:error, reason}`。
  """

  use Jido.Action,
    name: "compose_exam_from_bank",
    description:
      "Picks questions from a question bank to compose an exam paper matching the " <>
        "requested topic, types and difficulty. Returns validated question ids.",
    schema:
      Zoi.object(%{
        candidates: Zoi.list(Zoi.map()),
        topic: Zoi.string() |> Zoi.optional(),
        subject: Zoi.string() |> Zoi.optional(),
        count: Zoi.integer() |> Zoi.default(5),
        question_types: Zoi.list(Zoi.string()) |> Zoi.default(["single"]),
        difficulty: Zoi.integer() |> Zoi.optional(),
        knowledge_points: Zoi.list(Zoi.string()) |> Zoi.default([]),
        requirements: Zoi.string() |> Zoi.optional()
      })

  alias TcmEdu.AI.{ExamComposer, Qwen}

  require Logger

  @impl true
  def run(params, _context) do
    candidates = normalize_candidates(params[:candidates] || [])
    opts = selection_opts(params)

    baseline =
      case ExamComposer.select(candidates, opts) do
        {:ok, picked} -> Enum.map(picked, &to_string(&1.id))
        _ -> []
      end

    case select_with_llm(candidates, params) do
      {:ok, ids} ->
        case ExamComposer.validate(candidates, ids, opts) do
          {:ok, valid_ids} ->
            Logger.info("[ExamComposeAction] LLM selection: #{length(valid_ids)} questions")
            {:ok, %{question_ids: valid_ids}}

          {:error, reason} ->
            Logger.info(
              "[ExamComposeAction] LLM rejected (#{reason}), fallback to #{length(baseline)}"
            )

            {:ok, %{question_ids: baseline}}
        end

      {:error, _reason} ->
        {:ok, %{question_ids: baseline}}
    end
  end

  # ── LLM 选材 ─────────────────────────────────────────────

  defp select_with_llm([], _params), do: {:error, :no_candidates}

  defp select_with_llm(candidates, params) do
    prompt = build_prompt(candidates, params)

    messages = [
      %{role: "system", content: "你只输出合法 JSON 对象。不要 markdown 围栏，不要解释。"},
      %{role: "user", content: prompt}
    ]

    case Qwen.chat(messages, temperature: 0.2, max_tokens: 2048) do
      {:ok, raw} when is_binary(raw) and raw != "" ->
        raw
        |> strip_fences()
        |> Jason.decode()
        |> case do
          {:ok, %{"question_ids" => ids}} when is_list(ids) ->
            {:ok, Enum.map(ids, &to_string/1)}

          {:ok, %{"question_ids" => ids}} ->
            {:ok, ids}

          {:ok, other} ->
            {:error, "大模型返回格式异常：#{preview(other)}"}

          {:error, _} ->
            {:error, "大模型返回的不是合法 JSON"}
        end

      {:ok, _} ->
        {:error, "大模型返回了空内容"}

      {:error, reason} ->
        {:error, "大模型调用失败：#{format_reason(reason)}"}
    end
  end

  defp build_prompt(candidates, params) do
    topic = Map.get(params, :topic) || ""
    subject = Map.get(params, :subject) || "中医"
    count = Map.get(params, :count, 5)
    types = (params[:question_types] || ["single"]) |> Enum.join("、")
    difficulty = Map.get(params, :difficulty)
    knowledge_points = params[:knowledge_points] || []

    rows =
      candidates
      |> Enum.take(40)
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {q, i} ->
        "#{i}. [id:#{q.id}] 题型=#{q.type} 难度=#{q.difficulty} 知识点=#{Enum.join(q.knowledge_points || [], "、")} 题干=#{truncate(q.stem, 40)}"
      end)

    """
    你是资深医学命题专家，负责从题库中为一场考试选材组卷。
    - 试卷主题：#{topic}
    - 学科：#{subject}
    - 期望题数：#{count}
    - 允许题型：#{types}
    - 目标难度：#{difficulty || "不限"}（1 最易，5 最难）
    #{if knowledge_points != [], do: "- 知识点侧重：#{Enum.join(knowledge_points, "、")}\n", else: ""}\
    请从下面候选题目中挑选最合适的 #{count} 道题（题型尽量均衡、难度贴近目标、知识点贴合），
    只返回 JSON 对象，不要 markdown 围栏，不要解释，格式如下：

    {"question_ids": ["<第一题的 id>", "<第二题的 id>"]}

    候选题目：
    #{rows}
    """
  end

  # ── 归一化 ───────────────────────────────────────────────

  defp normalize_candidates(list) do
    list
    |> Enum.map(fn cand ->
      %{
        id: to_string(cand["id"] || cand[:id] || cand.id),
        stem: to_string(cand["stem"] || cand[:stem] || cand.stem || ""),
        type: normalize_type(cand["type"] || cand[:type] || cand.type),
        difficulty:
          normalize_difficulty(cand["difficulty"] || cand[:difficulty] || cand.difficulty),
        knowledge_points:
          normalize_kps(
            cand["knowledge_points"] || cand[:knowledge_points] || cand.knowledge_points
          )
      }
    end)
    |> Enum.reject(&(&1.id == ""))
  end

  defp normalize_type(t) when t in [:single, :multi, :judge, :essay], do: t
  defp normalize_type(t), do: t |> to_string() |> String.trim()

  defp normalize_difficulty(n) when is_integer(n), do: n |> max(1) |> min(5)
  defp normalize_difficulty(_), do: 3

  defp normalize_kps(nil), do: []
  defp normalize_kps(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_kps(_), do: []

  defp selection_opts(params) do
    [
      count: params[:count] || 5,
      question_types: params[:question_types] || ["single"],
      difficulty: params[:difficulty],
      knowledge_points: params[:knowledge_points] || []
    ]
  end

  defp strip_fences(raw) do
    raw
    |> String.trim()
    |> String.replace(~r/^```(?:json)?\s*\n/, "")
    |> String.replace(~r/\n```\s*$/, "")
    |> String.trim()
  end

  defp truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end

  defp preview(value) when is_binary(value), do: String.slice(value, 0, 60)
  defp preview(value), do: value |> inspect() |> String.slice(0, 60)

  defp format_reason(:missing_key), do: "未配置大模型 Key"
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
