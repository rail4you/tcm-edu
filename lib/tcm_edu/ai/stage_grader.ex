defmodule TcmEdu.AI.StageGrader do
  @moduledoc """
  阶段评分器：对学员在某临床阶段（问诊/查体/检查/诊断/鉴别/治疗/随访）的
  动作进行打分（0-100）并给出改进建议。

  评分维度按阶段侧重：

    * `:inquiry`        — 病史采集完整度（问全主诉/现病史/既往史/家族史/过敏史）
    * `:physical_exam`  — 查体动作规范与系统完整
    * `:auxiliary`      — 辅助检查选择合理性、避免过度检查
    * `:diagnosis`      — 诊断准确性、证据支撑
    * `:differential`   — 鉴别诊断全面性、排除逻辑
    * `:treatment`      — 治疗合理性、禁忌证把握
    * `:follow_up`      — 随访计划与复诊指标把握

  结合 `StandardPathwayComparator` 的对比结果（`gaps`）一起评估更准确；
  `gaps` 可直接用对比器输出的 missing/wrong_order/red_flag_missed。

  返回 `{:ok, %{score:, grade:, gaps:, suggestions:, feedback:}}`。
  """

  require Logger

  alias TcmEdu.AI.Qwen

  @default_max_tokens 1200
  @default_temperature 0.3

  @type grade_result :: %{
          score: integer(),
          grade: atom(),
          gaps: [String.t()],
          suggestions: [String.t()],
          feedback: String.t()
        }

  @doc """
  给某阶段评分。

  ## 参数

    * `opts`:
      * `:stage` (atom, required)
      * `:patient` (map, optional) — 病人快照（提供主诉/标准路径上下文）
      * `:student_actions` (list, required)
      * `:gaps` (list, optional) — 对比器给出的思维漏洞
      * `:model` (string, optional)
  """
  @spec grade(keyword()) :: {:ok, grade_result()} | {:error, term()}
  def grade(opts) when is_list(opts) or is_map(opts) do
    opts = Enum.into(opts, %{})
    stage = Map.get(opts, :stage) || Map.get(opts, "stage")
    actions = Map.get(opts, :student_actions) || Map.get(opts, "student_actions") || []

    cond do
      is_nil(stage) ->
        {:error, :missing_stage}

      actions == [] ->
        {:ok, empty_grade(stage)}

      true ->
        do_grade(stage, opts)
    end
  end

  defp do_grade(stage, opts) do
    messages = build_messages(stage, opts)

    case Qwen.chat(messages,
           model: opts[:model] || nil,
           max_tokens: opts[:max_tokens] || @default_max_tokens,
           temperature: opts[:temperature] || @default_temperature
         ) do
      {:ok, content} when is_binary(content) and content != "" ->
        parse_grade(content)

      {:ok, _} ->
        {:error, :empty}

      {:error, reason} ->
        Logger.warning("[StageGrader] LLM failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ── prompt ────────────────────────────────────────────────

  @dimension_specs %{
    inquiry: "病史采集完整度：主诉、现病史、既往史、家族史、过敏史、用药史是否问全",
    physical_exam: "查体规范与系统完整：生命体征、专科查体是否全面且顺序合理",
    auxiliary: "辅助检查选择合理性：该查的项目是否查了、是否避免过度检查且考虑禁忌",
    diagnosis: "诊断准确性：诊断是否成立、证据链是否完整、有无关键证据缺失",
    differential: "鉴别诊断全面性：是否考虑重要鉴别项并给出排除逻辑",
    treatment: "治疗合理性：方案是否规范、是否考虑禁忌证与合并症",
    follow_up: "随访计划：复诊时间、监测指标、健康教育与转诊把握是否到位"
  }

  defp build_messages(stage, opts) do
    patient = Map.get(opts, :patient) || Map.get(opts, "patient") || %{}
    actions = Map.get(opts, :student_actions) || Map.get(opts, "student_actions") || []
    gaps = Map.get(opts, :gaps) || Map.get(opts, "gaps") || []
    stage_label = TcmEdu.SimulatedPatient.ClinicalWorkflow.label(stage)
    dimension = Map.get(@dimension_specs, stage, "阶段综合表现")

    [
      %{
        role: "system",
        content:
          """
          你是一名临床医学教育评分专家。请对医学生在「#{stage_label}」阶段的表现打分，
          只输出严格 JSON。

          # 本阶段评分侧重

          #{dimension}

          # 输出格式（严格 JSON，不要 markdown 围栏）

              {
                "score": 78,
                "grade": "pass",
                "gaps": ["思维漏洞 1", "思维漏洞 2"],
                "suggestions": ["改进建议 1", "改进建议 2"],
                "feedback": "一句话总评（≤60 字）"
              }

          - score 为 0-100 整数；
          - grade ∈ excellent(90+)/good(80-89)/pass(70-79)/borderline(60-69)/fail(<60)；
          - gaps 1-4 条（已被功能标出的漏洞直接引用）；suggestions 1-4 条，给学生可执行建议。
          """
          |> String.trim()
      },
      %{
        role: "user",
        content:
          """
          # 病例主诉

          #{patient[:complaint] || patient["complaint"] || "（无）"}

          # 学员本阶段动作

          #{format_actions(actions)}

          # 已标注的思维漏洞

          #{format_gaps(gaps)}

          请评分并输出 JSON。
          """
          |> String.trim()
      }
    ]
  end

  # ── parsing ───────────────────────────────────────────────

  defp parse_grade(content) do
    stripped =
      content
      |> String.trim()
      |> strip_code_fence()

    case Jason.decode(stripped) do
      {:ok, obj} when is_map(obj) ->
        score = clamp_score(obj["score"] || obj[:score])
        grade = to_grade(obj["grade"] || obj[:grade] || grade_for(score))

        {:ok,
         %{
           score: score,
           grade: grade,
           gaps: list(obj["gaps"] || obj[:gaps]),
           suggestions: list(obj["suggestions"] || obj[:suggestions]),
           feedback: text(obj["feedback"] || obj[:feedback])
         }}

      # 防御：模型偶尔把 JSON 字符串再包一层引号，解码结果会是二进制
      {:ok, obj} when is_binary(obj) ->
        salvage_score(obj)

      {:error, _} ->
        salvage_score(stripped)
    end
  end

  # 非 JSON：尽力抽取分数
  defp salvage_score(text) do
    case Regex.run(~r/(?:score|分数|得分|分为|总分)\s*[:：为]?\s*(\d{1,3})/, text) do
      [_, n] ->
        score = clamp_score(String.to_integer(n))

        {:ok, %{score: score, grade: grade_for(score), gaps: [], suggestions: [], feedback: ""}}

      _ ->
        {:error, :parse_failed}
    end
  end

  defp empty_grade(stage) do
    %{
      score: 0,
      grade: :fail,
      gaps: ["#{TcmEdu.SimulatedPatient.ClinicalWorkflow.label(stage)}阶段未提交任何动作"],
      suggestions: ["请先完成本阶段的标准动作"],
      feedback: "本阶段未完成。"
    }
  end

  defp clamp_score(n) when is_integer(n), do: n |> max(0) |> min(100)
  defp clamp_score(n) when is_float(n), do: n |> trunc() |> max(0) |> min(100)
  defp clamp_score(_), do: 0

  defp grade_for(score) do
    cond do
      score >= 90 -> :excellent
      score >= 80 -> :good
      score >= 70 -> :pass
      score >= 60 -> :borderline
      true -> :fail
    end
  end

  defp to_grade(s) when s in [:excellent, :good, :pass, :borderline, :fail], do: s

  defp to_grade(s) when is_binary(s) do
    String.to_existing_atom(s)
  rescue
    _ -> :pass
  end

  defp to_grade(_), do: :pass

  defp list(nil), do: []
  defp list([]), do: []
  defp list(xs) when is_list(xs), do: Enum.map(xs, &text/1) |> Enum.reject(&(&1 == ""))
  defp list(_), do: []

  defp text(nil), do: ""
  defp text(s) when is_binary(s), do: String.trim(s)
  defp text(s), do: to_string(s)

  defp format_actions(actions) when is_list(actions) do
    actions
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {a, i} ->
      type = Map.get(a, :type) || Map.get(a, "type") || ""
      content = Map.get(a, :content) || Map.get(a, "content") || ""
      "#{i}. [#{type}] #{content}"
    end)
  end

  defp format_actions(_), do: "（无）"

  defp format_gaps([]), do: "（无）"

  defp format_gaps(gaps) when is_list(gaps) do
    gaps
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {g, i} -> "  #{i}. #{g}" end)
  end

  defp format_gaps(_), do: "（无）"

  defp strip_code_fence(text) do
    text
    |> String.replace(~r/^```(?:json)?\s*\n?/, "")
    |> String.replace(~r/\n?```\s*$/, "")
    |> String.trim()
  end
end
