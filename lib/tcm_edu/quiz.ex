defmodule TcmEdu.Quiz do
  @moduledoc """
  题库域（租户域）：题库 / 题目 / 作答记录。

  所有资源均为 `multitenancy :context`，调用时必须带
  `tenant: "tenant_<slug>"`（除非被 super_admin bypass）。
  """

  use Ash.Domain,
    otp_app: :tcm_edu

  resources do
    resource TcmEdu.Quiz.QuestionBank
    resource TcmEdu.Quiz.Question
    resource TcmEdu.Quiz.Attempt
    resource TcmEdu.Quiz.QuizJob
  end
end
