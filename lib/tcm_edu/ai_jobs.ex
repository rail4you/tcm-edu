defmodule TcmEdu.AIJobs do
  @moduledoc """
  AI 生成任务域（租户域）：备课 / 配图等异步生成任务的业务状态。

  与 `TcmEdu.Quiz`（出题任务 `QuizJob`）并列：本域承载出题之外的
  AI 生成任务，统一由 `TcmEdu.Workers.AiGenerationWorker` 在 Oban 中执行。
  """

  use Ash.Domain, otp_app: :tcm_edu

  resources do
    resource TcmEdu.AI.GenerationJob
  end
end
