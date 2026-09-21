defmodule TcmEdu.AI.MistakeExplainer do
  @moduledoc """
  AI 错题解析（合同 §1.6.3 · 学员智能刷题）。

  基于 `TcmEdu.AI.Qwen` 对学员错题生成：错因分析、知识点讲解、
  同类题练习建议。结果可缓存进 `TcmEdu.Quiz.Attempt.ai_explanation`。

  参考 KnowledgeHub 的 chat 用法：system prompt 约定输出结构。
  """

  require Logger

  alias TcmEdu.AI.Qwen

  @system_prompt """
  你是经验丰富的医学学业导师。学员做错了一道题，请解析：
  1. 正确思路（逐步讲清为什么这个答案对）
  2. 学员做错的可能原因（结合他选错的选项）
  3. 需要巩固的知识点
  4. 给出 2-3 道同类题的练习建议
  用 markdown 输出，语气鼓励、清楚。
  """

  @doc """
  解析一道错题。

  ## 参数

    * `question`    — 题目的 map/struct，含 `stem`、`options`、`answer`（正确答案）、`type`、`explanation`
    * `wrong_answer`— 学员答错的答案

  ## 返回

    * `{:ok, content}` — markdown 解析
    * `{:error, reason}`
  """
  @spec explain(map(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def explain(question, wrong_answer, opts \\ []) do
    user_content = build_prompt(question, wrong_answer)

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: user_content}
    ]

    case Qwen.chat(messages, opts) do
      {:ok, content} when is_binary(content) and content != "" ->
        {:ok, String.trim(content)}

      {:ok, _} ->
        {:error, :empty}

      {:error, reason} ->
        Logger.warning("[MistakeExplainer] failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_prompt(question, wrong_answer) do
    type = Map.get(question, :type) || Map.get(question, "type") || "题目"
    stem = Map.get(question, :stem) || Map.get(question, "stem") || "-"
    answer = Map.get(question, :answer) || Map.get(question, "answer") || "-"
    explanation = Map.get(question, :explanation) || Map.get(question, "explanation")
    options = Map.get(question, :options) || Map.get(question, "options") || []

    options_text =
      if Enum.any?(options) do
        options
        |> Enum.map_join("\n", fn opt ->
          label = opt["label"] || opt[:label]
          text = opt["text"] || opt[:text]
          "  #{label}. #{text}"
        end)
      else
        "（无选项）"
      end

    """
    题目（#{type}）：
    题干：#{stem}
    选项：
    #{options_text}
    正确答案：#{answer}#{if explanation, do: "\n参考答案解析：#{explanation}"}
    --------------------
    学员答错：#{wrong_answer}

    请按系统要求解析这道错题。
    """
    |> String.trim()
  end
end
