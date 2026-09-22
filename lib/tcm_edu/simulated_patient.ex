defmodule TcmEdu.SimulatedPatient do
  @moduledoc """
  模拟诊疗域（租户域）：教师可配置的「标准化病人」与学生对话练习。

  资源：

    * `TcmEdu.SimulatedPatient.Patient`        — 标准化病人档案（人设、主诉、病史、评分要点）
    * `TcmEdu.SimulatedPatient.Assignment`     — 教师把病人分配给学生
    * `TcmEdu.SimulatedPatient.Session`        — 学生与该病人的一次对话会话
    * `TcmEdu.SimulatedPatient.Message`        — 会话中的消息（学生 vs 病人）
    * `TcmEdu.SimulatedPatient.Evaluation`     — 对话结束后的 AI 评分记录

  所有资源均为 `multitenancy :context`，调用时必须带 `tenant: "tenant_<slug>"`。
  """

  use Ash.Domain,
    otp_app: :tcm_edu

  resources do
    resource TcmEdu.SimulatedPatient.Patient
    resource TcmEdu.SimulatedPatient.Assignment
    resource TcmEdu.SimulatedPatient.Session
    resource TcmEdu.SimulatedPatient.Message
    resource TcmEdu.SimulatedPatient.Evaluation
  end
end
