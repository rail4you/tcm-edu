defmodule TcmEdu.Courses do
  @moduledoc """
  课程域（租户域）：分类 / 课程 / 章节 / 课时。

  所有资源均为 `multitenancy :context`，调用时必须带
  `tenant: "tenant_<slug>"`（除非被 super_admin bypass）。
  """

  use Ash.Domain,
    otp_app: :tcm_edu

  resources do
    resource TcmEdu.Courses.CourseCategory
    resource TcmEdu.Courses.Course
    resource TcmEdu.Courses.Chapter
    resource TcmEdu.Courses.Lesson
  end
end
