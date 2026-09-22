defmodule TcmEdu.AI.ReasoningReportGeneratorTest do
  @moduledoc "`ReasoningReportGenerator` 测试。"

  use ExUnit.Case, async: false

  alias TcmEdu.AI.ReasoningReportGenerator

  @stub TcmEdu.AI.ReasoningReportGeneratorTest.Stub

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

  test "compute_dimensions 聚合六维（纯数值，不发 LLM）" do
    evals = [
      %{
        diagnosis_score: 80,
        differential_score: 70,
        treatment_score: 85,
        stage_scores: %{
          "inquiry" => 75,
          "physical_exam" => 60,
          "auxiliary" => 0,
          "follow_up" => 90
        }
      },
      %{
        diagnosis_score: 90,
        differential_score: 80,
        treatment_score: 95,
        stage_scores: %{"inquiry" => 85, "physical_exam" => 70, "auxiliary" => 80}
      }
    ]

    dims = ReasoningReportGenerator.compute_dimensions(evals)

    assert dims.diagnosis == 85
    assert dims.differential == 75
    assert dims.treatment == 90
    assert dims.inquiry == 80
    assert dims.physical_exam == 65
    # auxiliary 只有一次 >0（80）/一次 0（跳过）→ 80
    assert dims.auxiliary == 80
    assert dims.follow_up == 90
    assert dims.session_count == 2
    assert is_float(dims.total)
  end

  test "compute_dimensions 无数据时 total 0 / grade fail" do
    dims = ReasoningReportGenerator.compute_dimensions([])
    assert dims.total == 0.0
    assert dims.grade == :fail
  end

  test "compute_dimensions 使用 nil/缺失维度跳过" do
    dims =
      ReasoningReportGenerator.compute_dimensions([
        %{diagnosis_score: 60, differential_score: nil}
      ])

    assert dims.diagnosis == 60
    assert is_nil(dims.differential)
    assert is_nil(dims.treatment)
  end

  test "improvement_plan 解析 AI 返回的 JSON" do
    @stub.responses([
      Jason.encode!(%{
        "improvement_plan" => "多进行鉴别诊断训练，从典型病例拓展到复杂病例。",
        "dimension_report" => %{
          "diagnosis" => %{"score" => 72, "gap" => "依赖单一证据", "suggestion" => "补充证据链"},
          "differential" => %{"score" => 60, "gap" => "鉴别不全", "suggestion" => "列出常见鉴别"},
          "treatment" => %{"score" => 78, "gap" => "禁忌掌握不足", "suggestion" => "复习用药禁忌"}
        }
      })
    ])

    dims = %{diagnosis: 72, differential: 60, treatment: 78}

    assert {:ok, result} = ReasoningReportGenerator.improvement_plan(dimensions: dims)
    assert result.improvement_plan =~ "鉴别诊断"
    assert result.dimension_report[:diagnosis][:gap] == "依赖单一证据"
  end

  test "improvement_plan 缺维度 → :missing_dimensions" do
    assert {:error, :missing_dimensions} =
             ReasoningReportGenerator.improvement_plan(weaknesses: [])
  end

  test "generate 空 evaluation → :empty_evaluations" do
    assert {:error, :empty_evaluations} = ReasoningReportGenerator.generate(evaluations: [])
  end

  test "未配置 key → :missing_key" do
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    assert {:error, :missing_key} =
             ReasoningReportGenerator.improvement_plan(dimensions: %{diagnosis: 50})
  end
end

defmodule TcmEdu.AI.ReasoningReportGeneratorTest.Stub do
  @moduledoc false
  def responses(responses) do
    Process.put(:rrg_responses, responses)
  end

  def handle(conn) do
    case Process.get(:rrg_responses) do
      [resp | rest] ->
        Process.put(:rrg_responses, rest)
        content = if is_binary(resp), do: resp, else: Jason.encode!(resp)

        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"role" => "assistant", "content" => content}}]
        })

      _ ->
        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"role" => "assistant", "content" => ""}}]
        })
    end
  end
end
