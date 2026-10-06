defmodule TcmEdu.Enrollment do
  @moduledoc """
  选课域（租户域）：选课记录 + 学习进度。

  所有资源均为 `multitenancy :context`，调用时必须带
  `tenant: "tenant_<slug>"`（除非被 super_admin bypass）。
  """

  use Ash.Domain,
    otp_app: :tcm_edu,
    extensions: [AshJsonApi.Domain]

  resources do
    resource TcmEdu.Enrollment.Enrollment
    resource TcmEdu.Enrollment.Progress
  end
end
