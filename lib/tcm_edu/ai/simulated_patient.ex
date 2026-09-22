defmodule TcmEdu.AI.SimulatedPatient do
  @moduledoc """
  模拟诊疗：AI 扮演标准化病人（SP）。

  调用 `respond/2`，传入：

    * `:patient`   — `TcmEdu.SimulatedPatient.Patient`（或 `patient_snapshot` map），
      包含人设、主诉、病史、性格、说话方式、关键评分点
    * `:history`   — 最近的对话历史 `[%{role: "student"|"patient", content: "..."}]`
    * `:student_message` — 学生本轮提问/陈述
    * `:turn_index` — 当前轮次（用于在 prompt 中提示节奏）

  返回 `{:ok, %{reply: "病人说的话", metadata: %{revealed: [...]}}}`，
  `metadata.revealed` 列出本次发言里病人主动揭开的病史要点（供后续评分对照）。

  模型走 `TcmEdu.AI.Qwen`（qwen-flash），prompt 强调：

    * 始终保持 SP 的人设与说话方式；
    * 主诉 / 现病史只在被问及时才「揭开」；
    * 不会主动给出诊断 / 处方建议（那是学生该做的事）；
    * 鼓励学生，但不会明示评分。

  单元测试可用 `Application.put_env(:tcm_edu, TcmEdu.AI, req_options: [{:plug, {Req.Test, Stub}}])`
  注入 stub。
  """

  require Logger

  alias TcmEdu.AI.Qwen

  @type role :: String.t()
  @type message :: %{required(:role) => role(), required(:content) => String.t()}

  @default_max_tokens 1500
  @default_temperature 0.7

  @doc """
  生成 SP 的下一句回复。

  ## 参数

    * `opts`:
      * `:patient` (map, required) — 病人档案快照，至少含 name / complaint /
        history / personality / talking_style / key_points
      * `:history` (list, optional) — 历史消息，按时间顺序（不含本轮学生发言）
      * `:student_message` (string, required) — 学生本轮发言
      * `:turn_index` (integer, optional) — 当前学生轮次（0-based）
      * `:model` (string, optional) — 覆盖默认模型

  ## 返回

    * `{:ok, %{reply: String.t(), metadata: %{revealed: [String.t()]}}}` — SP 回复
    * `{:error, reason}` — 调用失败（`:missing_key` / LLM 错误等）
  """
  @spec respond(keyword()) :: {:ok, %{reply: String.t(), metadata: map()}} | {:error, term()}
  def respond(opts) when is_list(opts) or is_map(opts) do
    opts = Enum.into(opts, %{})
    patient = Map.get(opts, :patient) || Map.get(opts, "patient")
    history = Map.get(opts, :history) || Map.get(opts, "history") || []
    student_message = Map.get(opts, :student_message) || Map.get(opts, "student_message")

    cond do
      is_nil(patient) ->
        {:error, :missing_patient}

      is_nil(student_message) or student_message == "" ->
        {:error, :missing_student_message}

      true ->
        do_respond(patient, normalize_history(history), student_message, opts)
    end
  end

  defp do_respond(patient, history, student_message, opts) do
    messages = build_messages(patient, history, student_message, opts)

    case Qwen.chat(messages,
           model: opts[:model] || nil,
           max_tokens: opts[:max_tokens] || @default_max_tokens,
           temperature: opts[:temperature] || @default_temperature
         ) do
      {:ok, content} when is_binary(content) and content != "" ->
        # parse_reply/2 已返回 {:ok, %{reply:, metadata:}}，不要再包一层 ok
        parse_reply(content, patient)

      {:ok, _} ->
        {:error, :empty}

      {:error, reason} ->
        Logger.warning("[SimulatedPatient] LLM failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ── prompt ────────────────────────────────────────────────

  defp build_messages(patient, history, student_message, opts) do
    system = build_system_prompt(patient, opts)

    history_messages =
      Enum.map(history, fn %{role: role, content: content} ->
        cond do
          role == "student" ->
            %{role: "user", content: "[医生] #{content}"}

          role == "patient" ->
            %{role: "assistant", content: "[#{patient_name(patient)}] #{content}"}

          true ->
            %{role: "user", content: to_string(content)}
        end
      end)

    current = %{
      role: "user",
      content: "[医生] #{String.trim(student_message)}"
    }

    [%{role: "system", content: system}] ++ history_messages ++ [current]
  end

  defp build_system_prompt(patient, opts) do
    turn_index = opts[:turn_index] || 0
    min_questions = patient[:min_questions] || 8

    """
    你现在扮演一位「标准化病人（SP）」，和一位医生（医学生）进行门诊问诊对话。

    # 你的角色

    - 姓名：#{patient_name(patient)}
    - 性别/年龄：#{profile_field(patient, "gender", "未提供")} / #{profile_field(patient, "age", "未提供")}
    - 职业：#{profile_field(patient, "occupation", "未提供")}
    - 性格特点：#{patient[:personality] || "普通患者，略显焦虑"}
    - 说话方式：#{patient[:talking_style] || "用日常口语，句长中等"}

    # 主诉（你一开始就用这句话开场）

    > #{patient[:complaint] || ""}

    # 病史背景（仅在被问及时才逐步揭示）

    #{patient[:history] || "无特殊既往史。"}

    # 关键评分点（学生应该覆盖的要点）

    #{format_key_points(patient[:key_points] || [])}

    # 行为规则

    1. 你只能扮演病人，**不**给诊断、**不**开处方、**不**主动评价医生。
    2. 学生问什么，你按病史背景和性格特点如实/合理回答；不被问到不要主动倒出。
    3. 保持人设一致的说话方式：口语化、自然、有情绪反应（焦虑、回避、健谈等）。
    4. 当医生已问得差不多（≥ #{min_questions} 个问题），可以委婉询问：
       「医生，您觉得我大概是什么问题？接下来怎么办？」
       但**不要**直接告诉他答案。
    5. 单轮回复控制在 80 字以内；除非学生明确要求详细描述。
    6. 不要写旁白（如「（病人皱眉）」），也不要前缀「病人：」。
    7. 当前是问诊第 #{turn_index + 1} 轮；保持耐心，自然推进。

    # 输出格式（严格 JSON）

    只输出一行 JSON：

        {"reply": "病人说的话", "revealed": ["本轮新揭开的病史要点"]}

    `revealed` 可以是空数组；只有当学生问到了某条病史并且你据实回答时，
    才把它列入（例如「高血压 5 年」「父亲糖尿病」）。
    """
    |> String.trim()
  end

  # ── response parsing ─────────────────────────────────────

  defp parse_reply(content, patient) do
    stripped =
      content
      |> String.trim()
      |> strip_code_fence()

    case Jason.decode(stripped) do
      {:ok, %{"reply" => reply} = obj} when is_binary(reply) and reply != "" ->
        revealed = normalize_revealed(obj["revealed"])

        {:ok,
         %{reply: reply, metadata: %{revealed: revealed, patient_name: patient_name(patient)}}}

      {:ok, other} ->
        {:ok,
         %{
           reply: String.trim(Jason.encode!(other)),
           metadata: %{revealed: [], patient_name: patient_name(patient)}
         }}

      {:error, _} ->
        # LLM 没返回 JSON，回退到纯文本当作回复
        {:ok, %{reply: String.trim(content), metadata: %{revealed: []}}}
    end
  end

  defp normalize_revealed(nil), do: []
  defp normalize_revealed([]), do: []

  defp normalize_revealed(list) when is_list(list) do
    list
    |> Enum.map(fn
      s when is_binary(s) -> String.trim(s)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_revealed(_), do: []

  defp strip_code_fence(text) do
    text
    |> String.replace(~r/^```(?:json)?\s*\n?/, "")
    |> String.replace(~r/\n?```\s*$/, "")
    |> String.trim()
  end

  # ── helpers ───────────────────────────────────────────────

  defp patient_name(%{name: name}), do: name || "病人"
  defp patient_name(%{"name" => name}), do: name || "病人"
  defp patient_name(_), do: "病人"

  defp profile_field(patient, key, default) do
    case patient do
      %{^key => v} -> to_string(v)
      %{"profile" => %{} = profile} -> to_string(Map.get(profile, key, default))
      %{"profile" => profile} when is_map(profile) -> to_string(Map.get(profile, key, default))
      _ -> default
    end
  rescue
    _ -> default
  end

  defp format_key_points([]), do: "（教师未填写评分要点）"

  defp format_key_points(points) when is_list(points) do
    points
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {point, i} -> "  #{i}. #{point}" end)
  end

  defp normalize_history(history) when is_list(history) do
    Enum.flat_map(history, fn
      %{role: role, content: content} when role in ["student", "patient"] ->
        [%{role: role, content: to_string(content)}]

      _ ->
        []
    end)
  end

  defp normalize_history(_), do: []
end
