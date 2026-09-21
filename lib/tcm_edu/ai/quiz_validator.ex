defmodule TcmEdu.AI.QuizValidator do
  @moduledoc """
  AI 生成习题的结构化数据验证（纯函数，无 LLM 调用，可单测）。

  约定 LLM 返回 **JSON 数组**，每项形如：

      %{
        "type" => "single" | "multi" | "judge" | "essay",
        "stem" => "题干",
        "options" => [%{"label" => "A", "text" => "…", "correct" => true}],
        "answer" => "B" | "对" | "参考答案…",
        "explanation" => "解析（可选）",
        "difficulty" => 3,
        "knowledge_points" => ["肺经", "腧穴"]
      }

  `validate_items/2` 校验类型 / 题干 / 选项规则 / 答案一致性，
  并归一化为可直接写入 `TcmEdu.Quiz.Question` 的属性 map 列表：

    * 单选：恰好 1 个正确选项；`answer` 置为正确选项 label
    * 多选：至少 1 个正确选项；`answer` 为正确 label 拼接（如 `"AC"`）
    * 判断：`answer` 归一化为 `"对"` / `"错"`
    * 简答：`options` 置空，`answer` 为参考答案原文
  """

  @types ~w(single multi judge essay)
  @labels ~w(A B C D E F G H)

  @doc """
  校验并归一化 LLM 返回的数据。

  * `data` — 解码后的 JSON（期望为 list）
  * `opts` — `:max_count`（默认 20，截断多余题目）

  返回 `{:ok, [question_attrs]}` 或 `{:error, reason}`。
  """
  @spec validate_items(term(), keyword()) :: {:ok, [map()]} | {:error, String.t()}
  def validate_items(data, opts \\ [])

  def validate_items(data, opts) when is_list(data) do
    max_count = Keyword.get(opts, :max_count, 20)

    cond do
      data == [] ->
        {:error, "AI 返回了空题目列表"}

      length(data) > max_count ->
        data |> Enum.take(max_count) |> validate_all()

      true ->
        validate_all(data)
    end
  end

  def validate_items(%{} = single, opts) do
    # 兼容模型返回单个对象而非数组的情况
    validate_items([single], opts)
  end

  def validate_items(other, _opts) do
    {:error, "期望题目 JSON 数组，实际收到：#{preview(other)}"}
  end

  @doc "校验单个题目 map，返回归一化后的 Question 属性。"
  @spec validate_item(map(), pos_integer()) :: {:ok, map()} | {:error, String.t()}
  def validate_item(item, index \\ 1)

  def validate_item(item, index) when is_map(item) do
    with {:ok, type} <- fetch_type(item, index),
         {:ok, stem} <- fetch_stem(item, index),
         {:ok, difficulty} <- fetch_difficulty(item),
         {:ok, knowledge_points} <- fetch_knowledge_points(item),
         {:ok, explanation} <- fetch_explanation(item),
         {:ok, attrs} <- build_by_type(type, item, stem, index) do
      {:ok,
       Map.merge(attrs, %{difficulty: difficulty, knowledge_points: knowledge_points})
       |> maybe_put_explanation(explanation)}
    end
  end

  def validate_item(other, index) do
    {:error, "第 #{index} 题不是 JSON 对象：#{preview(other)}"}
  end

  # ── per-type builders ──────────────────────────────────────

  defp build_by_type("single", item, stem, index) do
    with {:ok, options} <- normalize_options(item, index, 2, 8),
         {:ok, correct} <- exactly_n_correct(options, 1, index, "单选题必须有且仅有 1 个正确答案") do
      {:ok,
       %{
         type: :single,
         stem: stem,
         options: options,
         answer: hd(correct).label
       }}
    end
  end

  defp build_by_type("multi", item, stem, index) do
    with {:ok, options} <- normalize_options(item, index, 2, 8),
         {:ok, correct} <- at_least_n_correct(options, 1, index, "多选题至少需要 1 个正确答案") do
      answer = correct |> Enum.map(& &1.label) |> Enum.join("")

      {:ok, %{type: :multi, stem: stem, options: options, answer: answer}}
    end
  end

  defp build_by_type("judge", item, stem, index) do
    case normalize_judge_answer(item["answer"] || item[:answer]) do
      {:ok, answer} ->
        {:ok, %{type: :judge, stem: stem, options: [], answer: answer}}

      :error ->
        {:error, "第 #{index} 题判断题答案必须是 对/错/正确/错误/true/false 之一"}
    end
  end

  defp build_by_type("essay", item, stem, index) do
    answer = item["answer"] || item[:answer] || ""

    if String.trim(to_string(answer)) == "" do
      {:error, "第 #{index} 题简答题缺少参考答案（answer）"}
    else
      {:ok, %{type: :essay, stem: stem, options: [], answer: String.trim(to_string(answer))}}
    end
  end

  # ── field fetchers ─────────────────────────────────────────

  defp fetch_type(item, index) do
    raw = item["type"] || item[:type] || "single"
    type = raw |> to_string() |> String.trim() |> String.downcase()

    if type in @types do
      {:ok, type}
    else
      {:error, "第 #{index} 题题型非法（#{preview(raw)}），只能是 #{Enum.join(@types, "/")}"}
    end
  end

  defp fetch_stem(item, index) do
    stem = item["stem"] || item[:stem] || item["question"] || item[:question] || ""

    if String.trim(to_string(stem)) == "" do
      {:error, "第 #{index} 题缺少题干（stem）"}
    else
      {:ok, String.trim(to_string(stem))}
    end
  end

  defp fetch_difficulty(item) do
    case item["difficulty"] || item[:difficulty] do
      nil ->
        {:ok, 3}

      n when is_integer(n) ->
        {:ok, clamp_difficulty(n)}

      n when is_float(n) ->
        {:ok, n |> trunc() |> clamp_difficulty()}

      s when is_binary(s) ->
        case Integer.parse(String.trim(s)) do
          {n, _} -> {:ok, clamp_difficulty(n)}
          :error -> {:ok, 3}
        end

      _ ->
        {:ok, 3}
    end
  end

  defp fetch_knowledge_points(item) do
    raw = item["knowledge_points"] || item[:knowledge_points] || item["knowledgePoints"] || []

    points =
      cond do
        is_list(raw) -> Enum.map(raw, &to_string/1)
        is_binary(raw) -> String.split(raw, ~r/[,，、]/)
        true -> []
      end
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    {:ok, points}
  end

  defp fetch_explanation(item) do
    {:ok, item["explanation"] || item[:explanation]}
  end

  # ── options ────────────────────────────────────────────────

  defp normalize_options(item, index, min, max) do
    raw = item["options"] || item[:options] || []

    unless is_list(raw) do
      {:error, "第 #{index} 题选项（options）必须是数组"}
    else
      cleaned =
        raw
        |> Enum.map(&normalize_option/1)
        |> Enum.reject(&(&1.text == ""))

      cond do
        length(cleaned) < min ->
          {:error, "第 #{index} 题有效选项不足 #{min} 个（实际 #{length(cleaned)} 个）"}

        length(cleaned) > max ->
          {:ok, cleaned |> Enum.take(max) |> relabel()}

        true ->
          {:ok, relabel(cleaned)}
      end
    end
  end

  defp normalize_option(opt) when is_map(opt) do
    text =
      (opt["text"] || opt[:text] || opt["content"] || opt[:content] || "")
      |> to_string()
      |> clean_option_text()
      |> String.trim()

    %{
      label: "",
      text: text,
      correct: !!(opt["correct"] || opt[:correct] || opt["is_correct"] || opt[:is_correct])
    }
  end

  # 兼容模型直接返回字符串选项（默认全错，由答案字母反推正确项的逻辑在外层处理不了，
  # 这里保持 correct=false，调用方 prompt 会要求对象格式；纯字符串视为格式错误上游已拦截）
  defp normalize_option(opt) when is_binary(opt) do
    %{label: "", text: opt |> clean_option_text() |> String.trim(), correct: false}
  end

  defp normalize_option(_), do: %{label: "", text: "", correct: false}

  # 去掉模型常带的 "A. " / "B、" 前缀，label 由我们统一重编
  defp clean_option_text(text) do
    text |> to_string() |> String.replace(~r/^[A-H][.、)\s]+/u, "")
  end

  defp relabel(options) do
    options
    |> Enum.with_index()
    |> Enum.map(fn {opt, idx} -> %{opt | label: Enum.at(@labels, idx)} end)
  end

  defp exactly_n_correct(options, n, index, message) do
    correct = Enum.filter(options, & &1.correct)

    if length(correct) == n, do: {:ok, correct}, else: {:error, "第 #{index} 题#{message}"}
  end

  defp at_least_n_correct(options, n, index, message) do
    correct = Enum.filter(options, & &1.correct)

    if length(correct) >= n, do: {:ok, correct}, else: {:error, "第 #{index} 题#{message}"}
  end

  defp normalize_judge_answer(raw) do
    case raw |> to_string() |> String.trim() |> String.downcase() do
      v when v in ["对", "正确", "true", "t", "是", "yes", "√"] -> {:ok, "对"}
      v when v in ["错", "错误", "false", "f", "否", "no", "×", "x"] -> {:ok, "错"}
      _ -> :error
    end
  end

  # ── helpers ────────────────────────────────────────────────

  defp validate_all(items) do
    results =
      Enum.with_index(items, 1) |> Enum.map(fn {item, idx} -> validate_item(item, idx) end)

    errors = for {:error, message} <- results, do: message

    if errors == [] do
      {:ok, for({:ok, attrs} <- results, do: attrs)}
    else
      {:error, Enum.join(errors, "；")}
    end
  end

  defp maybe_put_explanation(attrs, nil), do: attrs
  defp maybe_put_explanation(attrs, ""), do: attrs

  defp maybe_put_explanation(attrs, explanation),
    do: Map.put(attrs, :explanation, to_string(explanation) |> String.trim())

  defp clamp_difficulty(n) when n < 1, do: 1
  defp clamp_difficulty(n) when n > 5, do: 5
  defp clamp_difficulty(n), do: n

  defp preview(value) when is_binary(value), do: String.slice(value, 0, 60)
  defp preview(value), do: value |> inspect() |> String.slice(0, 60)
end
