defmodule TcmEdu.AI.MdtFacilitator do
  @moduledoc """
  MDT 会诊 AI 促动器：在会诊室中扮演多种角色。

  * `respond/1` — 以指定角色回应上一条学员发言：
      - `role`: "patient"（AI 扮演患者，只回答被问/被查的信息）
      - `role`: "dept:<科室>"（AI 扮演该科室专家，**坚持本科室立场**、依本科室视角）
  * `summarize/1` — 会诊结束时根据全部消息生成汇总结论（诊断/鉴别/治疗/采纳角色）。

  测试：`Application.put_env(:tcm_edu, TcmEdu.AI, req_options: [{:plug, {Req.Test, Stub}}])`。
  """

  require Logger

  alias TcmEdu.AI.Qwen

  @reply_max_tokens 1200
  @reply_temperature 0.6
  @sum_max_tokens 1600
  @sum_temperature 0.3

  @doc """
  以某角色回复一句话。

  ## 参数

    * `opts`:
      * `:case_snapshot` (map, required) — 会诊病例快照（主诉/病史/科室）
      * `:role` (string, required) — "patient" 或 "dept:内科"
      * `:history` (list, required) — 已有会诊消息 `[%{role:, content:}]`
      * `:student_message` (string, required) — 学员本轮发言
      * `:model` (string, optional)

  ## 返回

    * `{:ok, %{reply: String.t()}}`
    * `{:error, reason}`
  """
  @spec respond(keyword()) :: {:ok, map()} | {:error, term()}
  def respond(opts) when is_list(opts) or is_map(opts) do
    opts = Enum.into(opts, %{})
    case_snap = Map.get(opts, :case_snapshot) || Map.get(opts, "case_snapshot")
    role = Map.get(opts, :role) || Map.get(opts, "role")
    history = Map.get(opts, :history) || Map.get(opts, "history") || []
    msg = Map.get(opts, :student_message) || Map.get(opts, "student_message")

    cond do
      is_nil(case_snap) -> {:error, :missing_case}
      is_nil(role) -> {:error, :missing_role}
      is_nil(msg) or msg == "" -> {:error, :empty_message}
      true -> do_respond(case_snap, role, history, msg, opts)
    end
  end

  defp do_respond(case_snap, role, history, msg, opts) do
    messages = build_reply_messages(case_snap, role, history, msg)

    with {:ok, content} <-
           Qwen.chat(messages,
             model: opts[:model] || nil,
             max_tokens: opts[:max_tokens] || @reply_max_tokens,
             temperature: opts[:temperature] || @reply_temperature
           ) do
      {:ok, %{reply: String.trim(strip(content))}}
    else
      {:error, reason} ->
        Logger.warning("[MdtFacilitator] respond LLM failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  汇总整场会诊。

  ## 参数

    * `opts`:
      * `:case_snapshot` (map, required)
      * `:history` (list, required) — 全部会诊消息
      * `:model` (string, optional)

  ## 返回

    * `{:ok, %{primary_diagnosis:, differential:, treatment:, roles_considered:, summary:}}`
  """
  @spec summarize(keyword()) :: {:ok, map()} | {:error, term()}
  def summarize(opts) when is_list(opts) or is_map(opts) do
    opts = Enum.into(opts, %{})
    case_snap = Map.get(opts, :case_snapshot) || Map.get(opts, "case_snapshot")
    history = Map.get(opts, :history) || Map.get(opts, "history") || []

    cond do
      is_nil(case_snap) -> {:error, :missing_case}
      history == [] -> {:error, :empty_history}
      true -> do_summarize(case_snap, history, opts)
    end
  end

  defp do_summarize(case_snap, history, opts) do
    messages = build_summary_messages(case_snap, history)

    with {:ok, content} <-
           Qwen.chat(messages,
             model: opts[:model] || nil,
             max_tokens: opts[:max_tokens] || @sum_max_tokens,
             temperature: opts[:temperature] || @sum_temperature
           ) do
      parse_summary(content)
    else
      {:error, reason} ->
        Logger.warning("[MdtFacilitator] summarize LLM failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ── reply prompt ──────────────────────────────────────────

  defp build_reply_messages(case_snap, role, history, msg) do
    dep = if String.starts_with?(role, "dept:"), do: String.trim_leading(role, "dept:"), else: nil

    system =
      if role == "patient" do
        """
        你正在一场多学科会诊（MDT）中扮演患者。会诊目标是共同诊断病情。
        你只能据实回答被问到/被查到的信息（主诉、病史、症状），
        不主动替医生下结论、不主动给出诊断。保持真实患者语气，单轮 ≤ 80 字。
        """
        |> String.trim()
      else
        """
        你在多学科会诊（MDT）中扮演「#{dep}」科室专家。
        你要坚持本科室（#{dep}）的专业立场与检查/处理倾向，同时尊重其它科室意见。
        只许从本科室视角给出有见地的发言，语法 1-2 句（≤ 100 字），不要重复患者已说的。
        """
        |> String.trim()
      end

    [
      %{role: "system", content: system},
      %{
        role: "user",
        content:
          """
          # 会诊病例

          - 主诉：#{case_snap["complaint"] || case_snap[:complaint]}
          - 病史：#{case_snap["history"] || case_snap[:history] || "（无）"}
          - 可参与科室：#{format_departments(case_snap)}

          # 已有会诊讨论

          #{format_history(history)}

          # 当前需要你（#{role}）回应的发言

          > #{msg}

          请直接输出回应文本（不要前缀角色名，不要 json）。
          """
          |> String.trim()
      }
    ]
  end

  # ── summary prompt ────────────────────────────────────────

  defp build_summary_messages(case_snap, history) do
    [
      %{
        role: "system",
        content: """
        你是 MDT 会诊主持人，请综合整场会诊讨论，输出一个结构化结论（严格 JSON，不要 markdown 围栏）：
            {
              "primary_diagnosis": "会诊共同诊断",
              "differential": "需鉴别的疾病",
              "treatment": "最终处置/治疗方案（含跨科室协作）",
              "roles_considered": ["采纳意见的科室1", "科室2"],
              "summary": "两句以内的总结"
            }
        若讨论未收敛或缺失关键信息，在 summary 中指出分歧/缺口。
        """
        |> String.trim()
      },
      %{
        role: "user",
        content:
          """
          # 会诊病例

          - 主诉：#{case_snap["complaint"] || case_snap[:complaint]}
          - 期望方向：#{case_snap["expected_conclusion"] || case_snap[:expected_conclusion] || "（未给）"}

          # 完整会诊记录

          #{format_history(history)}

          请输出 JSON 结论。
          """
          |> String.trim()
      }
    ]
  end

  # ── parsing ───────────────────────────────────────────────

  defp parse_summary(content) do
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
           primary_diagnosis: text(obj["primary_diagnosis"] || obj[:primary_diagnosis]),
           differential: text(obj["differential"] || obj[:differential]),
           treatment: text(obj["treatment"] || obj[:treatment]),
           roles_considered: list(obj["roles_considered"] || obj[:roles_considered]),
           summary: text(obj["summary"] || obj[:summary])
         }}

      _ ->
        # 兜底：整段作为 summary
        {:ok,
         %{primary_diagnosis: "", differential: "", treatment: "", roles_considered: [], summary: stripped}}
    end
  end

  # ── helpers ───────────────────────────────────────────────

  defp text(nil), do: ""
  defp text(s) when is_binary(s), do: String.trim(s)
  defp text(s), do: to_string(s)

  defp list(nil), do: []
  defp list([]), do: []
  defp list(xs) when is_list(xs), do: Enum.map(xs, &text/1) |> Enum.reject(&(&1 == ""))
  defp list(_), do: []

  defp strip(text) do
    text
    |> String.replace(~r/\A["']/, "")
    |> String.replace(~r/["']\z/, "")
    |> String.trim()
  end

  defp format_departments(snap) do
    case snap["departments"] || snap[:departments] do
      deps when is_list(deps) and deps != [] -> Enum.join(deps, "、")
      _ -> "（未列）"
    end
  end

  defp format_history(history) do
    if history == [] do
      "（无）"
    else
      history
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {m, i} ->
        role = m.role
        content = String.trim(to_string(m.content || ""))
        "#{i}. [#{role}] #{content}"
      end)
    end
  end
end