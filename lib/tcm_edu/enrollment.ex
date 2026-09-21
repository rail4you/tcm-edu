defmodule TcmEdu.Enrollment do
  @moduledoc """
  选课域（租户域）：选课记录 + 学习进度。

  所有资源均为 `multitenancy :context`，调用时必须带
  `tenant: "tenant_<slug>"`（除非被 super_admin bypass）。
  """

  use Ash.Domain,
    otp_app: :tcm_edu,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource TcmEdu.Enrollment.Enrollment do
      rpc_action(:my_enrollments, :my_enrollments)
      rpc_action(:enroll_in_course, :enroll)
      rpc_action(:cancel_enrollment, :cancel)
      rpc_action(:complete_enrollment, :mark_completed)
    end

    resource TcmEdu.Enrollment.Progress do
      rpc_action(:upsert_progress, :upsert_progress)
      rpc_action(:update_progress, :update)
    end
  end

  resources do
    resource TcmEdu.Enrollment.Enrollment
    resource TcmEdu.Enrollment.Progress
  end
end
