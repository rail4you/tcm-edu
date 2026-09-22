defmodule TcmEdu.AI.StageGraderTest do
  @moduledoc "`StageGrader` 测试（Req.Test stub，不发真实请求）。"

  use ExUnit.Case, async: false

  alias TcmEdu.AI.StageGrader

  @stub TcmEdu.AI.StageGraderTest.Stub

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

  test "缺阶段 → :missing_stage" do
    assert {:error, :missing_stage} =
             StageGrader.grade(student_actions: [%{type: "ask", content: "x"}])
  end

  test "空动作 → fail 占位（不发 LLM）" do
    assert {:ok, %{score: 0, grade: :fail}} =
             StageGrader.grade(stage: :inquiry, student_actions: [])
  end

  test "成功：解析结构化 JSON" do
    @stub.responses([
      %{
        "score" => 82,
        "grade" => "good",
        "gaps" => ["未问过敏史"],
        "suggestions" => ["补充过敏史与家族史"],
        "feedback" => "信息采集较完整，遗漏过敏史。"
      }
    ])

    assert {:ok, result} =
             StageGrader.grade(
               stage: :inquiry,
               patient: %{complaint: "胸痛 2 月"},
               student_actions: [%{type: "ask", content: "胸痛多久了？"}],
               gaps: ["未问家族史"]
             )

    assert result.score == 82
    assert result.grade == :good
    assert result.gaps == ["未问过敏史"]
    assert result.suggestions == ["补充过敏史与家族史"]
  end

  test "非 JSON 兜底：抽取分数" do
    @stub.responses(["本次评分为 65 分，整体一般。"])

    assert {:ok, %{score: 65, grade: :borderline}} =
             StageGrader.grade(stage: :inquiry, student_actions: [%{type: "ask", content: "x"}])
  end

  test "未配置 key → :missing_key" do
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    assert {:error, :missing_key} =
             StageGrader.grade(stage: :inquiry, student_actions: [%{type: "ask", content: "x"}])
  end
end

defmodule TcmEdu.AI.StageGraderTest.Stub do
  @moduledoc false
  def responses(responses) do
    Process.put(:sg_responses, responses)
  end

  def handle(conn) do
    case Process.get(:sg_responses) do
      [resp | rest] ->
        Process.put(:sg_responses, rest)
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"role" => "assistant", "content" => (if is_binary(resp), do: resp, else: Jason.encode!(resp))}}]})

      _ ->
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"role" => "assistant", "content" => ""}}]})
    end
  end
end