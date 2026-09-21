defmodule TcmEdu.Quiz do
  @moduledoc """
  题库域（租户域）：题库 / 题目 / 作答记录。

  所有资源均为 `multitenancy :context`，调用时必须带
  `tenant: "tenant_<slug>"`（除非被 super_admin bypass）。
  """

  use Ash.Domain,
    otp_app: :tcm_edu,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource TcmEdu.Quiz.QuestionBank do
      rpc_action(:list_question_banks, :read)
      rpc_action(:get_question_bank, :read, get_by: [:id])
      rpc_action(:create_question_bank, :create)
      rpc_action(:update_question_bank, :update)
      rpc_action(:delete_question_bank, :destroy)
    end

    resource TcmEdu.Quiz.Question do
      rpc_action(:list_questions, :read)
      rpc_action(:list_questions_by_bank, :list_by_bank)
      rpc_action(:get_question, :read, get_by: [:id])
      rpc_action(:create_question, :create)
      rpc_action(:update_question, :update)
      rpc_action(:archive_question, :archive)
      rpc_action(:delete_question, :destroy)
    end

    resource TcmEdu.Quiz.Attempt do
      rpc_action(:list_attempts, :read)
      rpc_action(:submit_attempt, :submit)
      rpc_action(:my_attempts, :my_attempts)
      rpc_action(:my_mistakes, :my_mistakes)
    end
  end

  resources do
    resource TcmEdu.Quiz.QuestionBank
    resource TcmEdu.Quiz.Question
    resource TcmEdu.Quiz.Attempt
  end
end
