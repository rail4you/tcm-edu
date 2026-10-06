defmodule TcmEdu.Exam do
  @moduledoc """
  考试域（租户域）：试卷 / 组卷 / 分配 / 作答 / 批改。

  资源：
    * `TcmEdu.Exam.Exam`          — 试卷（手工组卷或 AI 智能组卷）
    * `TcmEdu.Exam.ExamQuestion`  — 试卷题目（题目 × 分值 × 顺序）
    * `TcmEdu.Exam.ExamAssignment`— 分配给学生的作答记录（状态机）
    * `TcmEdu.Exam.ExamResponse`  — 学生单题答案（客观题自动判分）
    * `TcmEdu.Exam.ExamJob`       — AI 智能组卷后台任务（Oban）

  多租户：所有资源均为 `multitenancy :context`，调用时必须带
  `tenant: "tenant_<slug>"`。
  """

  use Ash.Domain,
    otp_app: :tcm_edu,
    extensions: [AshPhoenix, AshJsonApi.Domain]

  resources do
    resource TcmEdu.Exam.Exam
    resource TcmEdu.Exam.ExamQuestion
    resource TcmEdu.Exam.ExamAssignment
    resource TcmEdu.Exam.ExamResponse
    resource TcmEdu.Exam.ExamJob
  end
end
