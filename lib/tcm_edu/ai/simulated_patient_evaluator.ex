defmodule TcmEdu.AI.SimulatedPatientEvaluator do
  @moduledoc """
  模拟诊疗 AI 评分（合同 §1.6.4 · 教师端 AI 教学评估）。

  学生结束与标准化病人的对话后，把完整对话记录交给 `TcmEdu.AI.Qwen`，
  按以下三个维度打分（每项 0-100）：

    * **专业度（professional）** —— 病史采集完整度、关键问诊点覆盖、
      诊断思路、避免漏诊/误诊
    * **同理心（empathy）** —— 对病人情绪的回应、安抚、人文关怀
    * **沟通技巧（communication）** —— 提问清晰度、倾听、不打断、
      解释通俗易懂、尊重病人

  加权总分按 `Patient.rubric` 计算（默认 50/25/25）。

  返回 `{:ok, evaluation_attrs}`（可直接写入 `SimulatedPatient.Evaluation`）
  或 `{:error, reason}`。

  注意：模型返回必须解析成结构化 JSON；这里用强 prompt + 容错回退：
  JSON 解析失败时尝试抽取数字；再失败才返回 error。
  """

  require Logger

  alias TcmEdu.AI.Qwen

  @default_max_tokens 2500
  @default_temperature 0.3

  @type evaluation_attrs :: %{
          :professional_score => integer(),
          :empathy_score => integer(),
          :communication_score => integer(),
          :total_score => Decimal.t(),
          :grade => atom(),
          :feedback => String.t(),
          :highlights => [String.t()],
          :weaknesses => [String.t()],
          :key_points_hit => [String.t()],
          :key_points_missed => [String.t()],
          :rubric_snapshot => map(),
          :transcript_tokens => integer(),
          :model => String.t()
        }

  @doc """
  对一次完整的模拟诊疗对话进行 AI 评分。

  ## 参数

    * `opts`:
      * `:patient_snapshot` (map, required) — 病人快照（含 rubric / key_points）
      * `:transcript` (list of `%{role: "student"|"patient", content: ...}`, required)
      * `:tenant` (string, optional) — 仅用于日志

  ## 返回

    * `{:ok, attrs}` — 评分属性，可直接写入 `SimulatedPatient.Evaluation`
    * `{:error, reason}` — 调用失败
  """
  @spec evaluate(keyword()) :: {:ok, evaluation_attrs()} | {:error, term()}
  def evaluate(opts) when is_list(opts) or is_map(opts) do
    opts = Enum.into(opts, %{})
    patient = Map.get(opts, :patient_snapshot) || Map.get(opts, "patient_snapshot")
    transcript = Map.get(opts, :transcript) || Map.get(opts, "transcript") || []

    cond do
      is_nil(patient) ->
        {:error, :missing_patient}

      transcript == [] ->
        {:error, :empty_transcript}

      true ->
        do_evaluate(patient, transcript, opts)
    end
  end

  defp do_evaluate(patient, transcript, opts) do
    messages = build_messages(patient, transcript)

    case Qwen.chat(messages,
           model: opts[:model] || nil,
           max_tokens: opts[:max_tokens] || @default_max_tokens,
           temperature: opts[:temperature] || @default_temperature
         ) do
      {:ok, content} when is_binary(content) and content != "" ->
        parse_and_finalize(content, patient, transcript)

      {:ok, _} ->
        {:error, :empty}

      {:error, reason} ->
        Logger.warning("[SimulatedPatientEvaluator] LLM failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ── prompt ────────────────────────────────────────────────

  defp build_messages(patient, transcript) do
    rubric = normalize_rubric(patient[:rubric] || patient["rubric"])
    key_points = patient[:key_points] || patient["key_points"] || []

    [
      %{
        role: "system",
        content:
          """
          你是一名资深医学教育评估专家，专注于「标准化病人（SP）问诊」的能力评估。
          请根据一段完整的医生（医学生）与 SP 的对话，从以下三个维度分别打分（0-100），
          并给出具体的高光 / 不足 / 评分要点覆盖情况 / 综合评语。

          # 评分维度

          - **专业度（professional）**：病史采集完整度、关键问诊点是否覆盖、
            鉴别诊断思路、是否漏掉重要信息（如伴随症状、既往史、家族史、过敏史等）。
          - **同理心（empathy）**：对病人情绪的识别与回应、安抚与支持、
            不冷漠不打断、人文关怀（特别是对焦虑 / 紧张 / 老年病人）。
          - **沟通技巧（communication）**：提问清晰有条理（开放式优先）、
            用词通俗易懂、倾听与确认、解释到位、尊重病人、不教训人。

          # 当前评分权重（rubric，总和必须为 100）

          - 专业度 #{rubric.professional}%
          - 同理心 #{rubric.empathy}%
          - 沟通技巧 #{rubric.communication}%

          加权总分 = Σ(维度分 × 权重/100)。

          # 评分等级

          - 优秀（excellent）：90-100
          - 良好（good）：80-89
          - 及格（pass）：70-79
          - 边缘（borderline）：60-69
          - 不及格（fail）：<60

          # 必须覆盖的关键问诊点（key_points）

          #{format_key_points(key_points)}

          请根据学生是否问到这些要点给出 `key_points_hit` 与 `key_points_missed` 列表。

          # 输出格式（严格 JSON，不要 markdown 围栏，不要解释）

              {
                "professional": 80,
                "empathy": 75,
                "communication": 70,
                "total": 76.5,
                "grade": "pass",
                "highlights": ["亮点 1", "亮点 2"],
                "weaknesses": ["不足 1", "不足 2"],
                "key_points_hit": ["问到了 X", "问到了 Y"],
                "key_points_missed": ["未问 Z"],
                "feedback": "综合评语 markdown 内容"
              }

          - 三个维度分必须是整数 0-100；
          - `total` 保留 1 位小数；
          - `grade` 必须是 excellent / good / pass / borderline / fail 之一；
          - `highlights` / `weaknesses` 各 2-4 条，每条不超过 40 字；
          - `feedback` 用中文 2-4 段 markdown，简洁具体，给学生可执行建议。
          """
          |> String.trim()
      },
      %{
        role: "user",
        content:
          """
          # SP 档案

          - 姓名：#{patient_name(patient)}
          - 主诉：#{patient[:complaint] || patient["complaint"]}
          - 病史背景：#{patient[:history] || patient["history"] || "（无）"}
          - 性格 / 说话方式：#{patient[:personality] || patient["personality"]} / #{patient[:talking_style] || patient["talking_style"]}

          # 对话记录（学生 = 医生，patient = SP）

          #{format_transcript(transcript)}

          请按上述要求输出 JSON 评分。
          """
          |> String.trim()
      }
    ]
  end

  # ── parsing ───────────────────────────────────────────────

  defp parse_and_finalize(content, patient, transcript) do
    stripped =
      content
      |> String.trim()
      |> strip_code_fence()

    case Jason.decode(stripped) do
      {:ok, obj} when is_map(obj) ->
        finalize(obj, patient, transcript, stripped)

      {:error, _} ->
        # 容错：尝试从文本里抽取关键字段
        case salvage(content) do
          {:ok, obj} ->
            finalize(obj, patient, transcript, stripped)

          {:error, reason} ->
            Logger.warning(
              "[SimulatedPatientEvaluator] parse failed: #{inspect(reason)}: #{String.slice(content, 0, 200)}"
            )

            {:error, {:parse_failed, reason}}
        end
    end
  end

  defp finalize(obj, patient, transcript, _raw) do
    rubric = normalize_rubric(patient[:rubric] || patient["rubric"])

    professional = clamp_score(obj["professional"] || obj[:professional])
    empathy = clamp_score(obj["empathy"] || obj[:empathy])
    communication = clamp_score(obj["communication"] || obj[:communication])

    total_decimal =
      compute_total(professional, empathy, communication, rubric)

    grade = obj["grade"] || obj[:grade] || grade_for(total_decimal)

    feedback =
      (obj["feedback"] || obj[:feedback] || "")
      |> to_string()
      |> String.trim()
      |> case do
        "" -> "（AI 未返回评语）"
        text -> text
      end

    attrs = %{
      professional_score: professional,
      empathy_score: empathy,
      communication_score: communication,
      total_score: total_decimal,
      grade: to_grade_atom(grade),
      feedback: feedback,
      highlights: normalize_string_list(obj["highlights"] || obj[:highlights]),
      weaknesses: normalize_string_list(obj["weaknesses"] || obj[:weaknesses]),
      key_points_hit: normalize_string_list(obj["key_points_hit"] || obj[:key_points_hit]),
      key_points_missed:
        normalize_string_list(obj["key_points_missed"] || obj[:key_points_missed]),
      rubric_snapshot: %{
        "professional" => rubric.professional,
        "empathy" => rubric.empathy,
        "communication" => rubric.communication
      },
      transcript_tokens: count_tokens(transcript),
      model: TcmEdu.AI.text_model()
    }

    {:ok, attrs}
  end

  # 从三个维度 + rubric 计算加权总分（保留 1 位小数）
  defp compute_total(p, e, c, rubric) do
    weighted =
      p * rubric.professional + e * rubric.empathy + c * rubric.communication

    Float.round(weighted / 100.0, 1)
    |> Decimal.from_float()
    |> Decimal.round(1)
  end

  defp clamp_score(n) when is_integer(n), do: n |> max(0) |> min(100)
  defp clamp_score(n) when is_float(n), do: n |> trunc() |> max(0) |> min(100)
  defp clamp_score(_), do: 0

  defp grade_for(total) do
    cond do
      total >= 90 -> "excellent"
      total >= 80 -> "good"
      total >= 70 -> "pass"
      total >= 60 -> "borderline"
      true -> "fail"
    end
  end

  defp to_grade_atom(s) when is_atom(s), do: s
  defp to_grade_atom(s) when is_binary(s), do: String.to_existing_atom(s)
  defp to_grade_atom(_), do: :pass

  defp normalize_rubric(nil), do: %{professional: 50, empathy: 25, communication: 25}

  defp normalize_rubric(%{} = map) do
    %{
      professional: clamp_pct(Map.get(map, :professional) || Map.get(map, "professional") || 50),
      empathy: clamp_pct(Map.get(map, :empathy) || Map.get(map, "empathy") || 25),
      communication:
        clamp_pct(Map.get(map, :communication) || Map.get(map, "communication") || 25)
    }
  end

  defp normalize_rubric(_), do: %{professional: 50, empathy: 25, communication: 25}

  defp clamp_pct(n) when is_integer(n) and n in 0..100, do: n
  defp clamp_pct(n) when is_float(n), do: n |> round() |> clamp_pct()
  defp clamp_pct(_), do: 25

  defp normalize_string_list(nil), do: []
  defp normalize_string_list([]), do: []

  defp normalize_string_list(list) when is_list(list) do
    list
    |> Enum.map(fn
      s when is_binary(s) -> String.trim(s)
      s -> s |> to_string() |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_string_list(_), do: []

  # 当 LLM 返回非 JSON 时，用正则做尽力而为的字段抽取
  defp salvage(content) do
    fields = %{}

    fields =
      Map.put(
        fields,
        "professional",
        extract_int(content, ~r/"?professional"?\s*[:：]\s*(\d{1,3})/i)
      )

    fields =
      Map.put(fields, "empathy", extract_int(content, ~r/"?empathy"?\s*[:：]\s*(\d{1,3})/i))

    fields =
      Map.put(
        fields,
        "communication",
        extract_int(content, ~r/"?communication"?\s*[:：]\s*(\d{1,3})/i)
      )

    if Enum.any?(Map.values(fields), &(&1 not in [nil, 0])) do
      {:ok, Map.put(fields, "feedback", "（AI 未返回结构化 JSON，评分为文本抽取结果）")}
    else
      {:error, :no_score_found}
    end
  end

  defp extract_int(text, regex) do
    case Regex.run(regex, text) do
      [_, n] -> String.to_integer(n)
      _ -> nil
    end
  end

  defp strip_code_fence(text) do
    text
    |> String.replace(~r/^```(?:json)?\s*\n?/, "")
    |> String.replace(~r/\n?```\s*$/, "")
    |> String.trim()
  end

  defp patient_name(%{name: name}), do: name || "病人"
  defp patient_name(%{"name" => name}), do: name || "病人"
  defp patient_name(_), do: "病人"

  defp format_key_points([]), do: "（无）"

  defp format_key_points(points) when is_list(points) do
    points
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {point, i} -> "  #{i}. #{point}" end)
  end

  defp format_transcript(transcript) do
    transcript
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {msg, i} ->
      role = if msg.role == "patient", do: "病人", else: "医生"
      content = String.trim(to_string(msg.content || ""))
      "#{i}. #{role}：#{content}"
    end)
  end

  # 粗略字数（用于日志 / 限额判断；不是真实 token）
  defp count_tokens(transcript) do
    transcript
    |> Enum.map(fn m -> to_string(m.content || "") |> String.length() end)
    |> Enum.sum()
  end
end
