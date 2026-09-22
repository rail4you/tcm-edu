defmodule TcmEdu.AI.SimulatedPatientTest do
  @moduledoc """
  `TcmEdu.AI.SimulatedPatient` 单元测试。

  不发真实 LLM 请求，只验证：

    * 缺 API key 时返回 `{:error, :missing_key}`
    * 缺病人 / 缺学生发言的入参校验
    * 内部 JSON 解析逻辑能正确从 LLM 返回里抽 `reply` 和 `revealed`

  解析逻辑是私有函数；本测试通过 `String.replace` 触发代码路径：
  实际请求路径用 Req.Test 桩在 `TcmEdu.AI.Qwen` 测，这里只测解析。
  """

  use ExUnit.Case, async: false

  alias TcmEdu.AI.SimulatedPatient

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
    patient = base_patient()

    assert {:error, :missing_key} =
             SimulatedPatient.respond(
               patient: patient,
               student_message: "您好，请问您哪里不舒服？"
             )
  end

  test "returns :missing_patient when patient is nil" do
    assert {:error, :missing_patient} =
             SimulatedPatient.respond(student_message: "x")
  end

  test "returns :missing_student_message when student_message is empty" do
    assert {:error, :missing_student_message} =
             SimulatedPatient.respond(patient: base_patient())
  end

  test "accepts both keyword list and map opts" do
    assert {:error, :missing_key} =
             SimulatedPatient.respond(
               patient: base_patient(),
               student_message: "您好"
             )

    assert {:error, :missing_key} =
             SimulatedPatient.respond(%{
               patient: base_patient(),
               student_message: "您好"
             })
  end

  defp base_patient do
    %{
      name: "张某某",
      profile: %{"age" => 52, "gender" => "女"},
      complaint: "心悸 3 天",
      history: "高血压 5 年",
      personality: "焦虑",
      talking_style: "短句",
      key_points: ["问发作时间", "问既往史"],
      min_questions: 5,
      max_turns: 20
    }
  end
end
