defmodule TcmEdu.Courses do
  @moduledoc """
  课程域（租户域）：分类 / 课程 / 章节 / 课时。

  所有资源均为 `multitenancy :context`，调用时必须带
  `tenant: "tenant_<slug>"`（除非被 super_admin bypass）。
  """

  use Ash.Domain,
    otp_app: :tcm_edu,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource TcmEdu.Courses.CourseCategory do
      rpc_action(:list_categories, :read)
      rpc_action(:create_category, :create)
      rpc_action(:update_category, :update)
      rpc_action(:delete_category, :destroy)
    end

    resource TcmEdu.Courses.Course do
      rpc_action(:list_courses, :read)
      rpc_action(:list_published_courses, :list_published)
      rpc_action(:list_teacher_courses, :list_by_teacher)
      rpc_action(:list_category_courses, :list_by_category)
      rpc_action(:get_course, :read, get_by: [:id])
      rpc_action(:list_popular_courses, :list_popular)
      rpc_action(:create_course, :create_course)
      rpc_action(:update_course, :update)
      rpc_action(:publish_course, :publish)
      rpc_action(:archive_course, :archive)
      rpc_action(:delete_course, :destroy)
    end

    resource TcmEdu.Courses.Chapter do
      rpc_action(:list_chapters, :read)
      rpc_action(:create_chapter, :create)
      rpc_action(:update_chapter, :update)
      rpc_action(:delete_chapter, :destroy)
    end

    resource TcmEdu.Courses.Lesson do
      rpc_action(:list_lessons, :read)
      rpc_action(:create_lesson, :create)
      rpc_action(:update_lesson, :update)
      rpc_action(:delete_lesson, :destroy)
    end
  end

  resources do
    resource TcmEdu.Courses.CourseCategory
    resource TcmEdu.Courses.Course
    resource TcmEdu.Courses.Chapter
    resource TcmEdu.Courses.Lesson
  end
end
