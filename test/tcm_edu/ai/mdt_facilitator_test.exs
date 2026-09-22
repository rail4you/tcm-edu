defmodule TcmEdu.AI.MdtFacilitatorTest do
  @moduledoc "`MdtFacilitator` 测试（Req.Test stub，不发真实请求）。"

  use ExUnit.Case, async: false

  alias TcmEdu.AI.MdtFacilitator

  @stub TcmEdu.AI.MdtFacilitatorTest.Stub

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

  test "respond 入参校验" do
    assert {:error, :missing_case} = MdtFacilitator.respond(role: "patient", history: [], student_message: "hi")
    assert {:error, :missing_role} = MdtFacilitator.respond(case_snapshot: snap(), history: [], student_message: "hi")
    assert {:error, :empty_message} = MdtFacilitator.respond(case_snapshot: snap(), role: "patient", history: [], student_message: "")
  end

  test "respond 作为 patient 返回患者发言" do
    @stub.responses(["胸口疼，出汗，喘不上气。"])

    assert {:ok, %{reply: reply}} =
             MdtFacilitator.respond(
               case_snapshot: snap(),
               role: "patient",
               history: [],
               student_message: "您感觉怎样？"
             )

    assert reply =~ "胸口疼"
  end

  test "respond 作为某科室专家返回带科室立场的发言" do
    @stub.responses(["我建议优先完善心电图，明确有无缺血改变。"])

    assert {:ok, %{reply: reply}} =
             MdtFacilitator.respond(
               case_snapshot: snap(),
               role: "dept:心血管内科",
               history: [%{role: "student:急诊科", content: "先判断有无急性心梗"}],
               student_message: "是否需要先做心电图？"
             )

    assert reply =~ "心电图"
  end

  test "summarize 解析结构化结论" do
    @stub.responses([
      Jason.encode!(%{
        "primary_diagnosis" => "急性ST段抬高型心肌梗死",
        "differential" => "主动脉夹层、肺栓塞",
        "treatment" => "直接PCI + 双抗",
        "roles_considered" => ["心血管内科", "急诊科"],
        "summary" => "会诊达成一致，建议尽早再灌注。"
      })
    ])

    assert {:ok, result} =
             MdtFacilitator.summarize(
               case_snapshot: snap(),
               history: [%{role: "student:心血管内科", content: "建议 PCI"}]
             )

    assert result.primary_diagnosis == "急性ST段抬高型心肌梗死"
    assert result.roles_considered == ["心血管内科", "急诊科"]
  end

  test "summarize 空历史 → :empty_history" do
    assert {:error, :empty_history} = MdtFacilitator.summarize(case_snapshot: snap(), history: [])
  end

  test "未配置 key → :missing_key" do
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    assert {:error, :missing_key} =
             MdtFacilitator.respond(
               case_snapshot: snap(),
               role: "patient",
               history: [],
               student_message: "hi"
             )
  end

  defp snap do
    %{
      "complaint" => "突发胸骨后压榨样疼痛 30 分钟",
      "history" => "高血压 10 年，吸烟 30 年",
      "departments" => ["急诊科", "心血管内科", "影像科"],
      "expected_conclusion" => "急性心肌梗死，尽早再灌注"
    }
  end
end

defmodule TcmEdu.AI.MdtFacilitatorTest.Stub do
  @moduledoc false
  def responses(responses) do
    Process.put(:mdt_responses, responses)
  end

  def handle(conn) do
    case Process.get(:mdt_responses) do
      [resp | rest] ->
        Process.put(:mdt_responses, rest)
        content = if is_binary(resp), do: resp, else: Jason.encode!(resp)
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"role" => "assistant", "content" => content}}]})

      _ ->
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"role" => "assistant", "content" => ""}}]})
    end
  end
end