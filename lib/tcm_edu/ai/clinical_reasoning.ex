defmodule TcmEdu.AI.ClinicalReasoning do
  @moduledoc """
  临床思维推理引擎（全流程模拟编排）。

  负责除「问诊对话」（由 `AI.SimulatedPatient` 处理）之外各阶段的信息揭示与
  阶段评估编排：

    * `reveal/1` — 根据学员在某阶段的动作，生成该阶段「揭示」内容
      （查体结果 / 辅助检查结果 / 诊断反馈 / 鉴别核对 / 治疗反应 / 随访印象）
    * `compare/1` — 委托 `StandardPathwayComparator` 实时对比标准路径
    * `grade/1`   — 委托 `StageGrader` 给阶段打分
    * `evaluate_stage/1` — 组合：先对比 → 带上思维漏洞评分 → 产出供 UI 展示的
      完整阶段评估（reveal + compare + grade）

  各玩家角色：

    * `:patient` — 模拟病人（问诊之外的阶段也由它扮演患者/检查结果讲述者）
    * `:examiner` — 体格检查主持人（按学员查体动作给出体征）
    * `:lab`      — 辅助检查报告（按学员开单给出结果，**只报已检的**）
    * `:consult`  — 会诊专家（诊断/鉴别/治疗阶段给出专科意见）

  测试：`Application.put_env(:tcm_edu, TcmEdu.AI, req_options: [{:plug, {Req.Test, Stub}}])`
  注入 stub。
  """

  require Logger

  alias TcmEdu.AI.Qwen
  alias TcmEdu.AI.StageGrader
  alias TcmEdu.AI.StandardPathwayComparator

  @default_max_tokens 1600
  @default_temperature 0.4

  # 各阶段的检查/查体信息来源（按阶段把 patient.history 相关部分给模型）
  @stage_roles %{
    physical_exam: :examiner,
    auxiliary: :lab,
    diagnosis: :consult,
    differential: :consult,
    treatment: :consult,
    follow_up: :consult
  }

  @doc """
  生成某阶段的「揭示」内容。

  ## 参数

    * `opts`:
      * `:patient` (map, required) — 病人快照
      * `:stage` (atom, required) — :physical_exam | :auxiliary | :diagnosis |
        :differential | :treatment | :follow_up（问诊走 `AI.SimulatedPatient`）
      * `:student_actions` (list, required) — 学员动作
      * `:turn_index` (integer, optional)
      * `:model` (string, optional)

  ## 返回

    * `{:ok, %{result_text: String.t(), findings: [String.t()], hints: [String.t()]}}`
    * `{:error, reason}`
  """
  @spec reveal(keyword()) :: {:ok, map()} | {:error, term()}
  def reveal(opts) when is_list(opts) or is_map(opts) do
    opts = Enum.into(opts, %{})
    patient = Map.get(opts, :patient) || Map.get(opts, "patient")
    stage = Map.get(opts, :stage) || Map.get(opts, "stage")
    actions = Map.get(opts, :student_actions) || Map.get(opts, "student_actions") || []

    cond do
      is_nil(patient) -> {:error, :missing_patient}
      is_nil(stage) -> {:error, :missing_stage}
      stage == :inquiry -> {:error, :inquiry_uses_simulated_patient}
      actions == [] -> {:ok, %{result_text: "", findings: [], hints: []}}
      true -> do_reveal(patient, stage, actions, opts)
    end
  end

  defp do_reveal(patient, stage, actions, opts) do
    messages = build_reveal_messages(patient, stage, actions, opts)

    with {:ok, content} <-
           Qwen.chat(messages,
             model: opts[:model] || nil,
             max_tokens: opts[:max_tokens] || @default_max_tokens,
             temperature: opts[:temperature] || @default_temperature
           ) do
      parse_reveal(content)
    else
      {:error, :empty} -> {:error, :empty}

      {:error, reason} ->
        Logger.warning("[ClinicalReasoning] reveal LLM failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ── reveal prompt ─────────────────────────────────────────

  defp build_reveal_messages(patient, stage, actions, opts) do
    role = Map.get(@stage_roles, stage, :examiner)
    stage_label = TcmEdu.SimulatedPatient.ClinicalWorkflow.label(stage)
    role_intro = role_intro(role, stage_label)
    turn_index = opts[:turn_index] || 0

    background = patient[:history] || patient["history"] || "（无）"

    [
      %{role: "system", content: role_intro},
      %{
        role: "user",
        content: """
        # 病例背景（仅作依据，不主动和盘托出）

        #{background}

        # 学员本阶段的动作

        #{format_actions(actions)}

        # 当前是#{stage_label}第 #{turn_index + 1} 轮

        请按角色输出 JSON。
        """
        |> String.trim()
      }
    ]
  end

  defp role_intro(:examiner, stage_label) do
    """
    你是一位进行#{stage_label}的医生助手。学员会给出查体动作清单。
    请逐项给出**学员实际做了的动作**对应的结果；学员没做的项目一律不给出。

    # 输出格式（严格 JSON，不要 markdown 围栏）

        {
          "result_text": "查体结果的完整叙述（100 字以内）",
          "findings": ["阳性体征 1", "阳性体征 2"],
          "hints": ["引导学员补充的查体提示（最多 2 条，无则空）"]
        }
    """
    |> String.trim()
  end

  defp role_intro(:lab, _stage_label) do
    """
    你是辅助检查/检验科的报告医师。学员会给出检查开单清单。
    请只对**学员已开的检查**返回结果；未开的检查不返回结论。
    异常结果必须明确标注（如 ↑、↓、阴性/阳性）。

    # 输出格式（严格 JSON，不要 markdown 围栏）

        {
          "result_text": "各项结果摘要（120 字以内）",
          "findings": ["异常结果条目"],
          "hints": ["建议补开的检查（最多 2 条）"]
        }
    """
    |> String.trim()
  end

  defp role_intro(:consult, stage_label) do
    """
    你是会诊专家，正在参与「#{stage_label}」阶段讨论。学员提交他们的判断/方案。
    请以专科立场回应：确认或纠正，指出逻辑漏洞，给出下一步建议。
    不要直接替学员完成，只做点评与引导。

    # 输出格式（严格 JSON，不要 markdown 围栏）

        {
          "result_text": "会诊意见（100 字以内）",
          "findings": ["要点 1", "要点 2"],
          "hints": ["建议学员补充的思考（最多 2 条）"]
        }
    """
    |> String.trim()
  end

  defp parse_reveal(content) do
    stripped =
      content
      |> String.trim()
      |> String.replace(~r/^```(?:json)?\s*\n?/, "")
      |> String.replace(~r/\n?```\s*$/, "")
      |> String.trim()

    case Jason.decode(stripped) do
      {:ok, obj} when is_map(obj) ->
        {:ok,
         %{
           result_text: text(obj["result_text"] || obj[:result_text]),
           findings: list(obj["findings"] || obj[:findings]),
           hints: list(obj["hints"] || obj[:hints])
         }}

      # 防御：模型偶尔把 JSON 字符串再包一层引号，解码结果会是二进制
      {:ok, obj} when is_binary(obj) ->
        {:ok, %{result_text: obj, findings: [], hints: []}}

      {:error, _} ->
        # 纯文本回退：整段当作 result_text
        {:ok, %{result_text: stripped, findings: [], hints: []}}
    end
  end

  # ── evaluate stage（组合编排）──────────────────────────────

  @doc """
  完整评估一个阶段：先实时对比标准路径，再带漏洞评分，最后生成揭示内容。

  ## 参数与 `reveal/1` 相同，额外：

    * `:skip_reveal?` (boolean, default false) — 诊断之后的阶段可由 UI 决定
      不展示揭示内容

  ## 返回

    * `{:ok, %{compare:, grade:, reveal:}}` — 三者均为对应模块的阶段结果；
      单个失败以 `{:error, ...}` 短路
  """
  @spec evaluate_stage(keyword()) :: {:ok, map()} | {:error, term()}
  def evaluate_stage(opts) when is_list(opts) or is_map(opts) do
    opts = Enum.into(opts, %{})
    patient = Map.get(opts, :patient) || Map.get(opts, "patient")
    stage = Map.get(opts, :stage) || Map.get(opts, "stage")
    actions = Map.get(opts, :student_actions) || Map.get(opts, "student_actions") || []

    with {:ok, patient} when not is_nil(patient) <- {:ok, patient},
         {:ok, stage} when not is_nil(stage) <- {:ok, stage},
         {:ok, compare} <-
           StandardPathwayComparator.compare(
             patient: patient,
             stage: stage,
             student_actions: actions,
             model: opts[:model] || nil
           ) do
      gaps = flatten_gaps(compare)

      with {:ok, grade} <-
             StageGrader.grade(
               patient: patient,
               stage: stage,
               student_actions: actions,
               gaps: gaps,
               model: opts[:model] || nil
             ),
           {:ok, reveal} <- maybe_reveal(opts, patient, stage, actions) do
        {:ok, %{compare: compare, grade: grade, reveal: reveal}}
      end
    end
  end

  defp maybe_reveal(opts, patient, stage, actions) do
    if opts[:skip_reveal?] == true or stage == :inquiry do
      {:ok, %{result_text: "", findings: [], hints: []}}
    else
      reveal(patient: patient, stage: stage, student_actions: actions, model: opts[:model] || nil)
    end
  end

  defp flatten_gaps(compare) do
    [
      compare.missing,
      compare.wrong_order,
      compare.red_flag_missed
    ]
    |> List.flatten()
    |> Enum.reject(&(&1 == ""))
  end

  # ── helpers ───────────────────────────────────────────────

  defp text(nil), do: ""
  defp text(s) when is_binary(s), do: String.trim(s)
  defp text(s), do: to_string(s)

  defp list(nil), do: []
  defp list([]), do: []
  defp list(xs) when is_list(xs), do: Enum.map(xs, &text/1) |> Enum.reject(&(&1 == ""))
  defp list(_), do: []

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
end