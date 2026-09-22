defmodule TcmEdu.Mdt do
  @moduledoc """
  多学科联合诊疗（MDT）模拟域（租户域）。

  支持多个学员分别扮演不同科室医生，AI 扮演患者与其他科室专家，共同完成
  一次会诊：患者主诉 → 各科自由发言 → 汇总出共同诊断与治疗/处置方案。

  资源：

    * `TcmEdu.Mdt.Case`      — 会诊病例档案（人设、主诉、病史、参与科室角色）
    * `TcmEdu.Mdt.Room`      — 一次具体的会诊室（关联病例、状态）
    * `TcmEdu.Mdt.Participant` — 会诊室参与者（学生 + 科室角色）
    * `TcmEdu.Mdt.Message`   — 会诊室消息（带 role：某科室 / 患者 / AI 专家）
    * `TcmEdu.Mdt.Conclusion`— 教师/汇总产生的共同诊断与处置方案

  所有资源均为 `multitenancy :context`，调用时必须带 `tenant: "tenant_<slug>"`。
  """

  use Ash.Domain,
    otp_app: :tcm_edu

  resources do
    resource TcmEdu.Mdt.Case
    resource TcmEdu.Mdt.Room
    resource TcmEdu.Mdt.Participant
    resource TcmEdu.Mdt.Message
    resource TcmEdu.Mdt.Conclusion
  end
end
