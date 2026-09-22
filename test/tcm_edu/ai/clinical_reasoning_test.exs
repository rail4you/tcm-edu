defmodule TcmEdu.AI.ClinicalReasoningTest do
  @moduledoc """
  `ClinicalReasoning` 引擎测试（Req.Test stub，不发真实请求）。

  覆盖：
    * reveal 入参校验（缺病人/缺阶段/问诊阶段）
    * reveal 空动作 → 空揭示
    * reveal 成功：结构化 JSON 与纯文本回退
    * evaluate_stage 编排：compare → grade → reveal 顺序消费
    * 未配置 key → :missing_key
  """

  use ExUnit.Case, async: false

  alias TcmEdu.AI.ClinicalReasoning

  @stub TcmEdu.AI.ClinicalReasoningTest.Stub

  setup do
    Application.put_env(:tcm_edu, TcmEdu.AI,
      api_key_override: "sk-test",
      base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
      text_model: "qwen-flash",
      timeout: 5_000,
      req_options: [plug: {Req.Test, @stub}]
    )

    on_exit(fn -> Application.delete_env(:tcm_edu, TcmEdu.AI) end)

    Req.Test.stub(@stub, &@stub.handle/1)
    :ok
  end

  test "reveal 缺参校验" do
    assert {:error, :missing_patient} = ClinicalReasoning.reveal(stage: :physical_exam, student_actions: [])
    assert {:error, :missing_stage} = ClinicalReasoning.reveal(patient: patient(), student_actions: [])

    assert {:error, :inquiry_uses_simulated_patient} =
             ClinicalReasoning.reveal(
               patient: patient(),
               stage: :inquiry,
               student_actions: [%{type: "ask", content: "x"}]
             )
  end

  test "reveal 空动作 → 空揭示（不发 LLM）" do
    assert {:ok, %{result_text: "", findings: [], hints: []}} =
             ClinicalReasoning.reveal(patient: patient(), stage: :physical_exam, student_actions: [])
  end

  test "reveal 成功：解析结构化 JSON" do
    @stub.responses([
      %{
        "result_text" => "双肺呼吸音清，未闻及干湿啰音。",
        "findings" => ["双肺呼吸音清"],
        "hints" => ["建议补充心率测量"]
      }
    ])

    assert {:ok, result} =
             ClinicalReasoning.reveal(
               patient: patient(),
               stage: :physical_exam,
               student_actions: [%{type: "exam", content: "肺部听诊"}]
             )

    assert result.result_text == "双肺呼吸音清，未闻及干湿啰音。"
    assert result.findings == ["双肺呼吸音清"]
  end

  test "reveal 非 JSON 回退取整段文本" do
    @stub.responses(["心电图示窦性心律，ST 段轻度压低。"])

    assert {:ok, %{result_text: text, findings: [], hints: []}} =
             ClinicalReasoning.reveal(
               patient: patient(),
               stage: :auxiliary,
               student_actions: [%{type: "order", content: "心电图"}]
             )

    assert text == "心电图示窦性心律，ST 段轻度压低。"
  end

  test "evaluate_stage 编排：compare → grade → reveal" do
    @stub.responses([
      # compare
      %{
        "matched" => ["肺部听诊"],
        "missing" => ["未测心率"],
        "wrong_order" => [],
        "red_flag_missed" => [],
        "notes" => "遗漏心率测量。"
      },
      # grade
      %{
        "score" => 74,
        "grade" => "pass",
        "gaps" => ["未测心率"],
        "suggestions" => ["补充生命体征测量"],
        "feedback" => "查体基本规范。"
      },
      # reveal
      %{
        "result_text" => "双肺呼吸音清。",
        "findings" => ["双肺呼吸音清"],
        "hints" => []
      }
    ])

    assert {:ok, %{compare: compare, grade: grade, reveal: reveal}} =
             ClinicalReasoning.evaluate_stage(
               patient: patient(),
               stage: :physical_exam,
               student_actions: [%{type: "exam", content: "肺部听诊"}]
             )

    assert compare.missing == ["未测心率"]
    assert grade.score == 74
    assert reveal.result_text == "双肺呼吸音清。"
  end

  test "evaluate_stage 空动作 → 空对比 + fail 评分（不发 LLM）" do
    assert {:ok, %{compare: %{missing: []}, grade: %{score: 0}}} =
             ClinicalReasoning.evaluate_stage(
               patient: patient(),
               stage: :auxiliary,
               student_actions: [],
               skip_reveal?: true
             )
  end

  test "未配置 key → :missing_key" do
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    assert {:error, :missing_key} =
             ClinicalReasoning.reveal(
               patient: patient(),
               stage: :physical_exam,
               student_actions: [%{type: "exam", content: "x"}]
             )
  end

  defp patient do
    %{
      name: "张某某",
      complaint: "胸痛 2 月",
      history: "高血压 5 年",
      difficulty_level: :advanced,
      red_flags: [],
      standard_pathway: %{
        physical_exam: %{must_perform: ["生命体征", "心肺听诊"]},
        auxiliary: %{lab_orders: ["心电图", "肌钙蛋白"]}
      }
    }
  end
end

defmodule TcmEdu.AI.ClinicalReasoningTest.Stub do
  @moduledoc false
  def responses(responses) do
    Process.put(:cr_responses, responses)
  end

  def handle(conn) do
    case Process.get(:cr_responses) do
      [resp | rest] ->
        Process.put(:cr_responses, rest)
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"role" => "assistant", "content" => (if is_binary(resp), do: resp, else: Jason.encode!(resp))}}]})

      _ ->
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"role" => "assistant", "content" => ""}}]})
    end
  end
end