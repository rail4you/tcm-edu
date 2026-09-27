defmodule TcmEdu.AI.ExamComposer do
  @moduledoc """
  智能组卷的纯逻辑（无 LLM 调用，可单测）。

  在给定题库候选题目里，按「题型分布 + 难度贴近 + 知识点覆盖」确定性地挑选
  若干道题组成一份试卷，并把总分均摊到每道题。

  这套逻辑承担两个角色：

    * 作为 AI 组卷的 **兜底**：当大模型选材失败或不可用时，保证组卷仍能完成；
    * 作为 **校验器**：验证大模型返回的题目 id 集合是否合法。

  候选题目约定为 map 列表，形如：

      %{id: "…", stem: "…", type: :single, difficulty: 3,
        knowledge_points: ["肺经"]}
  """

  @types ~w(single multi judge essay)

  @doc """
  从候选题目中确定性挑选题目。

  ## 选项

    * `:count`           — 期望题数（默认 5，最大 30）
    * `:question_types`  — 题型白名单（默认 `["single"]`）
    * `:difficulty`      — 目标难度 1-5，优先选贴近该难度的题
    * `:knowledge_points`— 知识点，命中越多越优先

  返回 `{:ok, [question_map]}`。候选不足时返回少于 `count` 的题目（可能为空）。
  """
  @spec select([map()], keyword()) :: {:ok, [map()]}
  def select(candidates, opts \\ []) do
    count = (opts[:count] || 5) |> clamp_count()
    types = normalize_types(opts[:question_types])
    difficulty = opts[:difficulty]
    knowledge_points = normalize_kps(opts[:knowledge_points])

    candidates = Enum.map(candidates, &normalize_candidate/1)
    pool = Enum.filter(candidates, &(&1.type in types))

    if pool == [] do
      {:ok, []}
    else
      ranked = rank(pool, difficulty, knowledge_points)
      by_type = Enum.group_by(ranked, & &1.type)
      {seen, acc} = round_robin(by_type, types, count, MapSet.new(), [])
      rest = Enum.filter(ranked, &(not MapSet.member?(seen, &1.id)))
      picked = Enum.reverse(acc) ++ Enum.take(rest, count - length(acc))
      {:ok, picked}
    end
  end

  @doc """
  校验大模型/外部返回的题目 id 集合。

  ## 参数

    * `candidates` — 候选题目（与 `select/2` 同构）
    * `ids`        — 待校验的 id 列表（可含重复）
    * `opts`       — `:count`（期望题数，用于上限约束）

  返回 `{:ok, ids}`（去重、去非法 id）或 `{:error, reason}`。
  """
  @spec validate([map()], [String.t()], keyword()) :: {:ok, [String.t()]} | {:error, String.t()}
  def validate(candidates, ids, opts \\ []) do
    ids = ids |> Enum.map(&to_string/1) |> Enum.uniq()
    valid_ids = MapSet.new(candidates, &to_string(&1.id))
    unknown = Enum.reject(ids, &MapSet.member?(valid_ids, &1))

    cond do
      ids == [] ->
        {:error, "AI 没有选出任何题目"}

      unknown != [] ->
        {:error, "AI 选中了不存在的题目：#{Enum.join(Enum.take(unknown, 3), "、")}"}

      length(ids) > (opts[:count] || 30) ->
        {:error, "AI 选中的题目超出上限"}

      true ->
        {:ok, ids}
    end
  end

  @doc """
  把总分均摊到选中题目上（整数分币，保证加总精确等于总分）。

  返回 `%{question_id => Decimal}`。
  """
  @spec distribute_scores([String.t()], integer()) :: %{optional(String.t()) => Decimal.t()}
  def distribute_scores(question_ids, total_score) do
    n = length(question_ids)

    if n == 0 do
      %{}
    else
      total_cents = total_score * 100
      base = div(total_cents, n)
      remainder = rem(total_cents, n)

      question_ids
      |> Enum.with_index()
      |> Map.new(fn {id, idx} ->
        cents = base + if(idx < remainder, do: 1, else: 0)
        {id, Decimal.new(1, cents, -2)}
      end)
    end
  end

  # ── 内部实现 ──────────────────────────────────────────────

  # 按匹配度排序：知识点命中数多者优先，难度距离近者优先，再按 id 稳定排序
  defp rank(pool, difficulty, kps) do
    Enum.sort_by(
      pool,
      fn q ->
        {Enum.count(q.knowledge_points || [], &(&1 in kps)), -difficulty_distance(q, difficulty),
         to_string(q.id)}
      end,
      :desc
    )
  end

  defp difficulty_distance(_q, nil), do: 0
  defp difficulty_distance(q, target), do: abs((q.difficulty || 3) - target)

  # 题型轮询（从上次命中的题型后一位继续），保证各题型都有覆盖
  defp round_robin(by_type, types, count, seen, acc, offset \\ 0) do
    if length(acc) >= count do
      {seen, acc}
    else
      case pick_rotating(by_type, types, seen, offset) do
        nil ->
          {seen, acc}

        {question, next_offset} ->
          round_robin(
            by_type,
            types,
            count,
            MapSet.put(seen, question.id),
            [question | acc],
            next_offset
          )
      end
    end
  end

  defp pick_rotating(by_type, types, seen, offset) do
    n = length(types)

    Enum.find_value(0..(n - 1), fn i ->
      type = Enum.at(types, rem(offset + i, n))

      case Enum.find(by_type[type] || [], &(not MapSet.member?(seen, &1.id))) do
        nil -> nil
        question -> {question, rem(offset + i + 1, n)}
      end
    end)
  end

  defp normalize_types(nil), do: @types

  defp normalize_types(types) when is_list(types) do
    cleaned =
      types
      |> Enum.map(&(&1 |> to_string() |> String.trim()))
      |> Enum.filter(&(&1 in @types))
      |> Enum.uniq()

    if cleaned == [], do: @types, else: cleaned
  end

  defp normalize_types(_), do: @types

  defp normalize_kps(nil), do: []
  defp normalize_kps(kps) when is_list(kps), do: Enum.map(kps, &to_string/1)
  defp normalize_kps(_), do: []

  # 候选 type 归一化为字符串，与题型白名单统一比较
  defp normalize_candidate(candidate) do
    type = candidate.type

    normalized =
      case type do
        t when is_atom(t) -> Atom.to_string(t)
        t when is_binary(t) -> t
        _ -> ""
      end

    Map.put(candidate, :type, normalized)
  end

  defp clamp_count(n) when is_integer(n), do: n |> max(1) |> min(30)
  defp clamp_count(_), do: 5
end
