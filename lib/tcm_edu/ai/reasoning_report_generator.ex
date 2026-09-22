defmodule TcmEdu.AI.ReasoningReportGenerator do
  @moduledoc """
  临床思维能力报告生成。

  把某学生在周期内的多次临床模拟 `Evaluation`（现在含诊断准确性/鉴别全面性/
  治疗合理性及阶段打分）聚合成六维能力分，并生成个性化提升计划。

  * `compute_dimensions/1` — 纯数值聚合（确定性、可单测，不依赖 LLM）
    - 六维：问诊 / 查体 / 检查 / 诊断准确性 / 鉴别全面性 / 治疗合理性 / 随访
    - 每个维度取该维度在历次会话的平均（无可用的该次记为跳过）
    - `total` 为六维均值；`grade` 对应等级
  * `improvement_plan/1` — 调用 LLM，根据维度分与短板生成提升计划 +
    逐维详细报告（诊断准确性 / 鉴别全面性 / 治疗合理性等短板与建议）
  * `generate/1` — 组合：compute + improvement_plan，产出可直接写入
    `SimulatedPatient.ClinicalReasoningReport` 的属性

  测试：`Application.put_env(:tcm_edu, TcmEdu.AI, req_options: [{:plug, {Req.Test, Stub}}])`。
  """

  require Logger

  alias TcmEdu.AI.Qwen

  @dims [:inquiry, :physical_exam, :auxiliary, :diagnosis, :differential, :treatment, :follow_up]

  @plan_max_tokens 1200
  @plan_temperature 0.3

  # Evaluation → 维度分取值（tuple: {score, whether this dim was assessed})
  @evaluation_dim_sources %{
    diagnosis: {[:diagnosis_score], true},
    differential: {[:differential_score], true},
    treatment: {[:treatment_score], true},
    inquiry: {[:stage_scores, "inquiry"], true},
    physical_exam: {[:stage_scores, "physical_exam"], true},
    auxiliary: {[:stage_scores, "auxiliary"], true},
    follow_up: {[:stage_scores, "follow_up"], true}
  }

  @doc "六个可打分维度（去重，诊断/鉴别/治疗为主要）"
  @spec dims() :: [atom()]
  def dims, do: @dims

  @doc """
  维度中文标签。
  """
  @spec dim_label(atom()) :: String.t()
  def dim_label(:inquiry), do: "问诊完整度"
  def dim_label(:physical_exam), do: "查体规范度"
  def dim_label(:auxiliary), do: "检查合理性"
  def dim_label(:diagnosis), do: "诊断准确性"
  def dim_label(:differential), do: "鉴别诊断全面性"
  def dim_label(:treatment), do: "治疗合理性"
  def dim_label(:follow_up), do: "随访把握"
  def dim_label(_), do: "—"

  @doc """
  纯数值聚合六维能力分。

  ## 参数

    * `evaluations` — Evaluation 记录/attrs 列表，每项可含
      `diagnosis_score`/`differential_score`/`treatment_score` 与
      `stage_scores`（map，键为字符串阶段名，值为该阶段分）。

  ## 返回

      %{
        inquiry: 0..100, physical_exam: .., auxiliary: ..,
        diagnosis: .., differential: .., treatment: .., follow_up: ..,
        total: float, grade: atom, session_count: integer
      }
  """
  @spec compute_dimensions([map()]) :: map()
  def compute_dimensions(evaluations) when is_list(evaluations) do
    evals = evaluations |> Enum.reject(&is_nil/1)

    scores =
      Map.new(@dims, fn dim ->
        {dim, average_dim(evals, dim)}
      end)

    assessed = scores |> Map.values() |> Enum.filter(&(not is_nil(&1)))

    total =
      if assessed == [] do
        0.0
      else
        Enum.sum(assessed) / length(assessed)
      end

    Map.merge(scores, %{
      total: Float.round(total, 1),
      grade: grade_for(total),
      session_count: length(evals)
    })
  end

  defp average_dim(evals, dim) do
    values =
      evals
      |> Enum.map(&dim_score(&1, dim))
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 <= 0))
      |> Enum.map(&clamp_score/1)

    case values do
      [] -> nil
      vs -> round(Enum.sum(vs) / length(vs))
    end
  end

  defp dim_score(eval, dim) do
    case @evaluation_dim_sources[dim] do
      {[score_key], _} ->
        Map.get(eval, score_key)

      {[stage_key, stage_name], _} ->
        stage_scores = Map.get(eval, stage_key) || %{}
        Map.get(stage_scores, stage_name) || Map.get(stage_scores, String.to_atom(stage_name))

      _ ->
        nil
    end
  end

  defp clamp_score(n) when is_integer(n), do: n |> max(0) |> min(100)
  defp clamp_score(n) when is_float(n), do: n |> trunc() |> max(0) |> min(100)
  defp clamp_score(_), do: nil

  defp grade_for(total) do
    cond do
      total >= 90 -> :excellent
      total >= 80 -> :good
      total >= 70 -> :pass
      total >= 60 -> :borderline
      true -> :fail
    end
  end

  @doc """
  根据维度分与短板调用 LLM 生成提升计划与逐维详细报告。

  ## 参数

    * `opts`:
      * `:dimensions` (map, required) — `compute_dimensions/1` 的输出
      * `:weaknesses` (list, optional) — 已有短板描述
      * `:model` (string, optional)

  ## 返回

    * `{:ok, %{improvement_plan: String.t(), dimension_report: map()}}`
    * `{:error, reason}`
  """
  @spec improvement_plan(keyword()) :: {:ok, map()} | {:error, term()}
  def improvement_plan(opts) when is_list(opts) or is_map(opts) do
    opts = Enum.into(opts, %{})
    dims = Map.get(opts, :dimensions) || Map.get(opts, "dimensions")
    weaknesses = Map.get(opts, :weaknesses) || Map.get(opts, "weaknesses") || []

    cond do
      is_nil(dims) -> {:error, :missing_dimensions}
      true -> do_plan(dims, weaknesses, opts)
    end
  end

  defp do_plan(dims, weaknesses, opts) do
    messages = build_messages(dims, weaknesses)

    with {:ok, content} <-
           Qwen.chat(messages,
             model: opts[:model] || nil,
             max_tokens: opts[:max_tokens] || @plan_max_tokens,
             temperature: opts[:temperature] || @plan_temperature
           ) do
      parse_plan(content)
    else
      {:error, reason} ->
        Logger.warning("[ReasoningReportGenerator] plan LLM failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_messages(dims, weaknesses) do
    summary =
      @dims
      |> Enum.map_join("\n", fn dim ->
        v = dims[dim]
        "- #{dim_label(dim)}：#{if is_nil(v), do: "（无数据）", else: v}"
      end)

    [
      %{
        role: "system",
        content:
          """
          你是临床医学教育导师，请根据学生的六维能力打分生成一份「临床思维能力报告」。
          输出严格 JSON，不要 markdown 围栏：
              {
                "improvement_plan": "面向短板的个性化提升计划（中文 markdown，长短各1段）",
                "dimension_report": {
                  "diagnosis": {"score": 72, "gap": "短板描述", "suggestion": "改进建议"},
                  "differential": {"score": 60, "gap": "...", "suggestion": "..."},
                  "treatment": {"score": 78, "gap": "...", "suggestion": "..."}
                }
              }
          重点诊断准确性、鉴别诊断全面性、治疗合理性三项；提升计划可执行、具体。
          """
          |> String.trim()
      },
      %{
        role: "user",
        content:
          """
          # 六维能力分

          #{summary}

          # 已知短板

          #{Enum.map_join(weaknesses, "\n", &"- #{&1}")}

          请生成报告。
          """
          |> String.trim()
      }
    ]
  end

  defp parse_plan(content) do
    stripped = strip_fence(String.trim(content))

    case Jason.decode(stripped) do
      {:ok, obj} when is_map(obj) ->
        dimension_report =
          normalize_dimension_report(obj["dimension_report"] || obj[:dimension_report])

        {:ok,
         %{
           improvement_plan: text(obj["improvement_plan"] || obj[:improvement_plan]),
           dimension_report: dimension_report
         }}

      _ ->
        {:ok, %{improvement_plan: stripped, dimension_report: %{}}}
    end
  end

  defp normalize_dimension_report(m) when is_map(m) do
    Enum.reduce(@evaluation_dim_sources, %{}, fn {dim, _}, acc ->
      if item = m[to_string(dim)] || m[dim] do
        Map.put(acc, dim, %{
          score: clamp_score(item["score"] || item[:score]),
          gap: text(item["gap"] || item[:gap]),
          suggestion: text(item["suggestion"] || item[:suggestion])
        })
      else
        acc
      end
    end)
  end

  defp normalize_dimension_report(_), do: %{}

  @doc """
  组合：compute + improvement_plan，产出可写入 `ClinicalReasoningReport` 的属性。
  """
  @spec generate(keyword()) :: {:ok, map()} | {:error, term()}
  def generate(opts) when is_list(opts) or is_map(opts) do
    opts = Enum.into(opts, %{})
    evals = Map.get(opts, :evaluations) || Map.get(opts, "evaluations") || []

    if evals == [] do
      {:error, :empty_evaluations}
    else
      dims = compute_dimensions(evals)
      weaknesses = Map.get(opts, :weaknesses) || []

      with {:ok, plan} <- improvement_plan(dimensions: dims, weaknesses: weaknesses) do
        {:ok,
         %{
           inquiry_score: dims.inquiry || 0,
           physical_exam_score: dims.physical_exam || 0,
           auxiliary_score: dims.auxiliary || 0,
           diagnosis_score: dims.diagnosis || 0,
           differential_score: dims.differential || 0,
           treatment_score: dims.treatment || 0,
           follow_up_score: dims.follow_up || 0,
           total_score: Decimal.from_float(dims.total) |> Decimal.round(1),
           grade: dims.grade,
           session_count: dims.session_count,
           improvement_plan: plan.improvement_plan,
           dimension_report: plan.dimension_report
         }}
      end
    end
  end

  defp text(nil), do: ""
  defp text(s) when is_binary(s), do: String.trim(s)
  defp text(s), do: to_string(s)

  defp strip_fence(t) do
    t
    |> String.replace(~r/^```(?:json)?\s*\n?/, "")
    |> String.replace(~r/\n?```\s*$/, "")
    |> String.trim()
  end
end
