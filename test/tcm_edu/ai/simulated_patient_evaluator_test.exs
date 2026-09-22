defmodule TcmEdu.AI.SimulatedPatientEvaluatorTest do
  @moduledoc """
  `TcmEdu.AI.SimulatedPatientEvaluator` 单元测试。

  不发真实 LLM 请求：

    * 缺 API key 时返回 `{:error, :missing_key}`
    * 缺病人 / 空 transcript 的入参校验
  """

  use ExUnit.Case, async: false

  alias TcmEdu.AI.SimulatedPatientEvaluator

  setup do
    old = Application.get_env(:tcm_edu, TcmEdu.AI)
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    on_exit(fn ->
      case old do
        nil -> Application.delete_env(:tcm_edu, TcmEdu.AI)
        env -> Application.put_env(:tcm_edu, TcmEdu.AI, env)
      end
    end)

    :ok
  end

  test "returns :missing_key when no API key is configured" do
    assert {:error, :missing_key} =
             SimulatedPatientEvaluator.evaluate(
               patient_snapshot: base_snapshot(),
               transcript: base_transcript()
             )
  end

  test "returns :missing_patient when snapshot is nil" do
    assert {:error, :missing_patient} =
             SimulatedPatientEvaluator.evaluate(transcript: base_transcript())
  end

  test "returns :empty_transcript when transcript is empty" do
    assert {:error, :empty_transcript} =
             SimulatedPatientEvaluator.evaluate(patient_snapshot: base_snapshot())
  end

  defp base_snapshot do
    %{
      name: "张某某",
      complaint: "心悸 3 天",
      history: "高血压 5 年",
      personality: "焦虑",
      talking_style: "短句",
      key_points: ["问发作时间"],
      rubric: %{"professional" => 50, "empathy" => 25, "communication" => 25}
    }
  end

  defp base_transcript do
    [
      %{role: "student", content: "您好，哪里不舒服？"},
      %{role: "patient", content: "我最近有点心慌。"}
    ]
  end
end
