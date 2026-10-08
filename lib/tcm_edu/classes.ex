defmodule TcmEdu.Classes do
  @moduledoc """
  班级域（租户域）：以独立实体 `ClassGroup` 组织学生。

  班级作为可长期引用的实体（而非裸字符串），好处：

    * 学生通过稳定的 `class_group_id` 归属，重命名班级无需回填数据；
    * 可按班级筛选/统计学生；
    * 预留班主任、年级、开课等班级级元数据。

  所有资源均为 `multitenancy :context`，调用时必须带
  `tenant: "tenant_<slug>"`（除非被 super_admin bypass）。
  """

  use Ash.Domain,
    otp_app: :tcm_edu,
    extensions: [AshPhoenix]

  resources do
    resource TcmEdu.Classes.ClassGroup
  end
end
