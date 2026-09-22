defmodule TcmEdu.AI.StandardPathwayComparator do
  @moduledoc """
  临床思维实时对比引擎：把学员某阶段的动作与 `Patient.standard_pathway` 的标准
  诊疗路径对比，实时标注思维漏洞。

  对比结果结构（`compare_result`）：

      %{
        matched: ["已覆盖标准动作…"],
        missing: ["遗漏标准动作…"],
        wrong_order: ["顺序不当…"],
        red_flag_missed: ["未识别危重信号…"],
        notes: "一句话总结"
      }

  输入 `student_actions` 是结构化动作数组（由阶段 UI / `AI.ClinicalReasoning`
  产生），每条形如 `%{type: "ask"|"exam"|"order"|"diagnosis"|"tx"|"follow_up",
  content: "具体动作描述"}`。

  引擎策略（按难度分级调整严格度）：

    * `:introductory` — 高提示：任何已覆盖动作都给 matched，missing 只列关键项
    * `:advanced`      — 中提示：正常标注
    * `:expert`        — 低提示：更严格，漏一条也给 missing，顺序弹性放宽
    * `:emergency`     — red flag 强约束：必须在 `red_flags` 覆盖，否则
      `red_flag_missed` 报警且整体警示

  测试：`Application.put_env(:tcm_edu, TcmEdu.AI, req_options: [{:plug, {Req.Test, Stub}}])`
  注入 stub；无 key / 失败时返回 `{:error, reason}`。
  """

  require Logger

  alias TcmEdu.AI.Qwen

  @type student_action :: %{required(:type) => String.t(), required(:content) => String.t()}
  @type compare_result :: %{
          matched: [String.t()],
          missing: [String.t()],
          wrong_order: [String.t()],
          red_flag_missed: [String.t()],
          notes: String.t()
        }

  @default_max_tokens 1500
  @default_temperature 0.2

  @doc """
  对比学员动作与标准路径。

  ## 参数

    * `opts`:
      * `:patient` (map, required) — 病人快照（至少含 standard_pathway、red_flags、difficulty_level）
      * `:stage` (atom, required) — 当前阶段（:inquiry … :follow_up）
      * `:student_actions` (list, required) — 结构化动作列表
      * `:model` (string, optional)

  ## 返回

    * `{:ok, compare_result()}` — 对比结果
    * `{:error, reason}` — 失败（缺参 / LLM 失败）
  """
  @spec compare(keyword()) :: {:ok, compare_result()} | {:error, term()}
  def compare(opts) when is_list(opts) or is_map(opts) do
    opts = Enum.into(opts, %{})
    patient = Map.get(opts, :patient) || Map.get(opts, "patient")
    stage = Map.get(opts, :stage) || Map.get(opts, "stage")
    actions = Map.get(opts, :student_actions) || Map.get(opts, "student_actions") || []

    cond do
      is_nil(patient) ->
        {:error, :missing_patient}

      is_nil(stage) ->
        {:error, :missing_stage}

      actions == [] ->
        {:ok, empty_result()}

      true ->
        do_compare(patient, stage, actions, opts)
    end
  end

  defp do_compare(patient, stage, actions, opts) do
    messages = build_messages(patient, stage, actions)

    case Qwen.chat(messages,
           model: opts[:model] || nil,
           max_tokens: opts[:max_tokens] || @default_max_tokens,
           temperature: opts[:temperature] || @default_temperature
         ) do
      {:ok, content} when is_binary(content) and content != "" ->
        parse_result(content)

      {:ok, _} ->
        {:error, :empty}

      {:error, reason} ->
        Logger.warning("[StandardPathwayComparator] LLM failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ── prompt ────────────────────────────────────────────────

  defp build_messages(patient, stage, actions) do
    level = normalize_level(patient[:difficulty_level] || patient["difficulty_level"])
    level_label = TcmEdu.SimulatedPatient.ClinicalWorkflow.difficulty_label(level)
    stage_label = TcmEdu.SimulatedPatient.ClinicalWorkflow.label(stage)

    pathway = patient[:standard_pathway] || patient["standard_pathway"] || %{}
    stage_standard = pathway[stage] || pathway[to_string(stage)] || %{}
    red_flags = patient[:red_flags] || patient["red_flags"] || []

    strictness =
      case level do
        :introductory -> "宽松（高提示）"
        :advanced -> "标准"
        :expert -> "严格（低提示，漏列即算遗漏）"
        :emergency -> "最严格（red flag 强约束）"
        _ -> "标准"
      end

    [
      %{
        role: "system",
        content:
          """
          你是一名临床医学教育评估专家，负责把医学生在某临床阶段采取的动作，
          与病例的「标准诊疗路径」实时对比，识别学生的思维漏洞。

          学生动作是结构化列表。请输出四项：

          - **matched**：学生动作中符合标准路径的条目（原文改写，不超过 30 字/条）
          - **missing**：标准路径要求但学生未做的动作（按标准路径逐条核对，最多 6 条）
          - **wrong_order**：顺序 / 优先级不当的动作（例如急诊先诊断后处理、未先排查危重）
          - **red_flag_missed**：应优先识别的危重信号（red flag）被遗漏或未处置

          规则：

          - 只输出严格 JSON，不要 markdown 围栏，不要解释。
          - matched/missing/wrong_order/red_flag_missed 都是字符串数组，可为空。
          - notes 是一句话总结（≤ 50 字）。
          - 审慎度：#{strictness}。
          - 急诊病例 red_flags 若未全部覆盖，必须在 red_flag_missed 中列出。
          """
          |> String.trim()
      },
      %{
        role: "user",
        content:
          """
          # 病例

          - 难度分级：#{level_label}
          - 当前阶段：#{stage_label}（#{stage}）

          # 患者标准路径（本阶段）

          #{format_map(stage_standard)}

          # 急诊危重信号（red_flags）

          #{format_red_flags(red_flags)}

          # 学生本科阶段动作

          #{format_actions(actions)}

          请对比并输出 JSON。
          """
          |> String.trim()
      }
    ]
  end

  # ── parsing ───────────────────────────────────────────────

  defp parse_result(content) do
    stripped =
      content
      |> String.trim()
      |> strip_code_fence()

    case Jason.decode(stripped) do
      {:ok, obj} when is_map(obj) ->
        {:ok, normalize(obj)}

      {:error, _} ->
        {:ok, salvage(stripped)}
    end
  end

  # 归一化：只保留四类已知键，并保证数组与 notes 字段存在
  defp normalize(obj) do
    %{
      matched: list(obj["matched"] || obj[:matched]),
      missing: list(obj["missing"] || obj[:missing]),
      wrong_order: list(obj["wrong_order"] || obj[:wrong_order]),
      red_flag_missed: list(obj["red_flag_missed"] || obj[:red_flag_missed]),
      notes: text(obj["notes"] || obj[:notes], "")
    }
  end

  # 非 JSON 兜底：从文本抽取数组
  defp salvage(content) do
    %{
      matched: extract_array(content, "matched"),
      missing: extract_array(content, "missing"),
      wrong_order: extract_array(content, "wrong_order"),
      red_flag_missed: extract_array(content, "red_flag_missed"),
      notes: "（AI 未返回结构化 JSON，对比为文本抽取结果）"
    }
  end

  defp extract_array(text, key) do
    case Regex.run(~r/"#{key}"\s*:\s*(\[[^\]]*\])/, text) do
      [_, json] ->
        case Jason.decode(json) do
          {:ok, list} when is_list(list) -> list
          _ -> []
        end

      _ ->
        []
    end
  end

  defp empty_result do
    %{matched: [], missing: [], wrong_order: [], red_flag_missed: [], notes: ""}
  end

  defp list(nil), do: []
  defp list([]), do: []
  defp list(xs) when is_list(xs), do: Enum.map(xs, &text(&1, "")) |> Enum.reject(&(&1 == ""))
  defp list(_), do: []

  defp text(nil, _default), do: ""
  defp text("", _default), do: ""
  defp text(s, _default) when is_binary(s), do: String.trim(s)
  defp text(_, default), do: default

  defp format_map(nil), do: "（病例未配置本阶段标准路径）"
  defp format_map(""), do: "（病例未配置本阶段标准路径）"

  defp format_map(map) when is_map(map) and map_size(map) > 0 do
    map
    |> Enum.map_join("\n", fn {k, v} -> "- #{format_map_value(k, v)}" end)
  end

  defp format_map(_), do: "（病例未配置本阶段标准路径）"

  defp format_map_value(k, v) when is_list(v), do: "#{k}：#{Enum.join(v, "；")}"
  defp format_map_value(k, v) when is_binary(v), do: "#{k}：#{v}"
  defp format_map_value(k, v), do: "#{k}：#{inspect(v)}"

  defp format_red_flags([]), do: "（无）"

  defp format_red_flags(flags) when is_list(flags) do
    flags |> Enum.with_index(1) |> Enum.map_join("\n", fn {f, i} -> "  #{i}. #{f}" end)
  end

  defp format_red_flags(_), do: "（无）"

  defp format_actions(actions) when is_list(actions) do
    if actions == [] do
      "（学生本阶段尚无动作）"
    else
      actions
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {a, i} ->
        type = Map.get(a, :type) || Map.get(a, "type") || to_string(Map.get(a, "type") || "")
        content = Map.get(a, :content) || Map.get(a, "content") || ""
        "#{i}. [#{type}] #{content}"
      end)
    end
  end

  defp format_actions(_), do: "（学生本阶段尚无动作）"

  defp strip_code_fence(text) do
    text
    |> String.replace(~r/^```(?:json)?\s*\n?/, "")
    |> String.replace(~r/\n?```\s*$/, "")
    |> String.trim()
  end

  defp normalize_level(nil), do: nil

  defp normalize_level(l) when l in [:introductory, :advanced, :expert, :emergency], do: l

  defp normalize_level(l) when is_binary(l) do
    String.to_existing_atom(l)
  rescue
    _ -> nil
  end

  defp normalize_level(_), do: nil
end
