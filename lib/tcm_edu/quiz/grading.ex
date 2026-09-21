defmodule TcmEdu.Quiz.Grading do
  @moduledoc """
  客观题判分（纯函数）。

  支持题型：
    * `:single` — 单选：答案等于正确选项的 label
    * `:multi`  — 多选：答案集合等于正确 label 集合（顺序无关）
    * `:judge`  — 判断：答案归一化后等于 `answer`（对/错、true/false、T/F）
    * `:essay`  — 主观题：不自动判分，返回 `nil`（由教师/AI 批改）

  ## 用法

      iex> question = %{type: :single, options: [%{"label" => "A", "correct" => true}, %{"label" => "B"}]}
      iex> TcmEdu.Quiz.Grading.grade(question, "A")
      true
  """

  @doc """
  判断作答是否正确。主观题返回 `nil`（无法自动判分）。
  """
  @spec grade(map(), String.t() | nil) :: boolean() | nil
  def grade(%{type: :essay}, _answer), do: nil

  def grade(%{type: :judge} = question, answer) do
    normalize_judge(answer) == normalize_judge(question.answer)
  end

  def grade(%{type: :multi} = question, answer) do
    submitted = normalize_labels(answer)
    correct = correct_labels(question.options)
    submitted != [] and submitted == correct
  end

  def grade(%{type: :single} = question, answer) do
    normalize_labels(answer) == correct_labels(question.options)
  end

  def grade(_question, _answer), do: nil

  @doc """
  写出判分结果（`is_correct` + `score`）到 Attempt。

  由 `Attempt.submit` 的 `after_action` 调用；主观题不改动。
  """
  def grade_and_persist(attempt) do
    question = load_question(attempt)

    case grade(question, attempt.answer) do
      nil ->
        {:ok, attempt}

      is_correct ->
        attempt
        |> Ash.Changeset.for_update(:grade, %{
          is_correct: is_correct,
          score: if(is_correct, do: 100, else: 0)
        })
        |> Ash.update(tenant: attempt_tenant(attempt), authorize?: false)
    end
  end

  # ── internals ────────────────────────────────────────────────────────

  defp load_question(%{question: %TcmEdu.Quiz.Question{} = q}), do: q

  defp load_question(attempt) do
    require Ash.Query

    TcmEdu.Quiz.Question
    |> Ash.Query.filter(id: attempt.question_id)
    |> Ash.read_one!(tenant: attempt_tenant(attempt), authorize?: false)
  end

  defp attempt_tenant(attempt) do
    attempt.__metadata__[:tenant] || "tenant_default"
  end

  defp correct_labels(options) when is_list(options) do
    options
    |> Enum.filter(&truthy(&1["correct"] || &1[:correct]))
    |> Enum.map(&to_string(&1["label"] || &1[:label]))
    |> Enum.map(&String.upcase/1)
    |> Enum.sort()
  end

  defp correct_labels(_), do: []

  # "A" / "A,B" / ["A", "B"] / ["A,B"] → 排序后的 label 列表
  defp normalize_labels(nil), do: []

  defp normalize_labels(answer) when is_list(answer) do
    answer |> Enum.flat_map(&normalize_labels/1) |> Enum.uniq() |> Enum.sort()
  end

  defp normalize_labels(answer) when is_binary(answer) do
    answer
    |> String.split(~r/[,\s、，;；]+/, trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.upcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_judge(nil), do: nil

  defp normalize_judge(value) do
    case value |> to_string() |> String.trim() |> String.downcase() do
      v when v in ["对", "正确", "true", "t", "yes", "y", "1", "是"] -> true
      v when v in ["错", "错误", "false", "f", "no", "n", "0", "否"] -> false
      other -> other
    end
  end

  defp truthy(nil), do: false
  defp truthy(false), do: false
  defp truthy("false"), do: false
  defp truthy(_), do: true
end
