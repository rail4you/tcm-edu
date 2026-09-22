defmodule TcmEdu.AI.StandardPathwayComparatorTest do
  @moduledoc """
  `StandardPathwayComparator` 测试（Req.Test stub，不发真实请求）。

  覆盖：
    * 入参校验（缺病人 / 缺阶段）
    * 空动作 → 空对比结果（不发请求）
    * 成功：解析结构化 JSON
    * 成功：非 JSON 兜底（数组抽取）
    * 未配置 key → {:error, :missing_key}
  """

  use ExUnit.Case, async: false

  alias TcmEdu.AI.StandardPathwayComparator

  @stub TcmEdu.AI.StandardPathwayComparatorTest.Stub

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

  test "缺病人 → :missing_patient" do
    assert {:error, :missing_patient} =
             StandardPathwayComparator.compare(
               stage: :inquiry,
               student_actions: [%{type: "ask", content: "x"}]
             )
  end

  test "缺阶段 → :missing_stage" do
    assert {:error, :missing_stage} =
             StandardPathwayComparator.compare(patient: patient(), student_actions: [])
  end

  test "空动作 → 空对比结果（不发 LLM）" do
    assert {:ok, %{matched: [], missing: [], wrong_order: [], red_flag_missed: [], notes: ""}} =
             StandardPathwayComparator.compare(
               patient: patient(),
               stage: :auxiliary,
               student_actions: []
             )
  end

  test "成功：解析结构化 JSON" do
    @stub.responses([
      %{
        "matched" => ["询问胸痛放射", "询问持续时间"],
        "missing" => ["未问家族史"],
        "wrong_order" => [],
        "red_flag_missed" => [],
        "notes" => "整体不错，家族史遗漏"
      }
    ])

    assert {:ok, result} =
             StandardPathwayComparator.compare(
               patient: patient(),
               stage: :inquiry,
               student_actions: [
                 %{type: "ask", content: "胸痛多久了？"},
                 %{type: "ask", content: "疼的时候会放射到哪里？"}
               ]
             )

    assert result.matched == ["询问胸痛放射", "询问持续时间"]
    assert result.missing == ["未问家族史"]
    assert result.notes == "整体不错，家族史遗漏"
  end

  test "非 JSON 兜底：抽取数组字段" do
    @stub.responses([
      "学生的动作基本合规。\"matched\": [\"问主诉\", \"问用药\"], \"missing\": [\"未问过敏史\"]"
    ])

    assert {:ok, result} =
             StandardPathwayComparator.compare(
               patient: patient(),
               stage: :inquiry,
               student_actions: [%{type: "ask", content: "哪里不舒服？"}]
             )

    assert result.matched == ["问主诉", "问用药"]
    assert result.missing == ["未问过敏史"]
  end

  test "未配置 key → :missing_key" do
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    assert {:error, :missing_key} =
             StandardPathwayComparator.compare(
               patient: patient(),
               stage: :inquiry,
               student_actions: [%{type: "ask", content: "x"}]
             )
  end

  defp patient do
    %{
      name: "张某某",
      complaint: "胸痛 2 月",
      difficulty_level: :advanced,
      red_flags: ["意识改变", "血压骤降"],
      standard_pathway: %{
        inquiry: %{
          must_ask: ["胸痛部位与放射", "持续时间与诱因", "既往史与家族史"]
        },
        auxiliary: %{
          lab_orders: ["心电图", "肌钙蛋白"],
          imaging: ["胸部 CT"]
        }
      }
    }
  end
end

defmodule TcmEdu.AI.StandardPathwayComparatorTest.Stub do
  @moduledoc false
  # 利用 Req.Test stub 返回预置响应队列（顺序消费，测试进程内顺序请求）
  def responses(responses) do
    Process.put(:spc_responses, responses)
  end

  def handle(conn) do
    case Process.get(:spc_responses) do
      [resp | rest] ->
        Process.put(:spc_responses, rest)

        Req.Test.json(conn, %{
          "choices" => [
            %{
              "message" => %{
                "role" => "assistant",
                "content" => if(is_binary(resp), do: resp, else: Jason.encode!(resp))
              }
            }
          ]
        })

      _ ->
        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"role" => "assistant", "content" => ""}}]
        })
    end
  end
end
