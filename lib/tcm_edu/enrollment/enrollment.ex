defmodule TcmEdu.Enrollment.Enrollment do
  @moduledoc """
  选课记录（租户域）：学生 ↔ 课程 N:M。

  * 同一课程不可重复选课（`unique_user_course` identity，冲突时 422）
  * 只能选已发布课程（`enroll` 内联校验）
  * `user_id` 强制取 actor，不接受客户端传入（防冒认）

  多租户：`multitenancy :context`，调用必须带 `tenant: "tenant_<slug>"`。
  """

  use Ash.Resource,
    domain: TcmEdu.Enrollment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  require Ash.Query

  multitenancy do
    strategy :context
  end

  # 学员端 JSON:API（`/api/student/enrollments*`）
  json_api do
    type("enrollment")

    # 一次请求带出课程树 + 我的课时进度，移动端「我的学习」列表单次取全
    includes([{:course, [chapters: [:lessons]]}, :progress_records])

    routes do
      base("/student/enrollments")

      # 首页统计（generic action，无 `:id` 段，与 index 不同层级、互不遮蔽）
      route(:get, "/overview", :overview)

      index(:my_enrollments)
      post(:enroll)
    end
  end

  postgres do
    table("enrollments")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :status, :atom do
      default(:active)
      constraints(one_of: [:active, :cancelled, :completed])
      public?(true)
    end

    attribute :enrolled_at, :utc_datetime do
      default(&DateTime.utc_now/0)
      public?(true)
    end

    attribute :expires_at, :utc_datetime do
      public?(true)
    end

    attribute :completed_at, :utc_datetime do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :user, TcmEdu.Accounts.User do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :course, TcmEdu.Courses.Course do
      allow_nil?(false)
      public?(true)
    end

    has_many :progress_records, TcmEdu.Enrollment.Progress do
      destination_attribute(:enrollment_id)
      public?(true)
    end
  end

  identities do
    identity(:unique_user_course, [:user_id, :course_id])
  end

  code_interface do
    define(:my_enrollments, action: :my_enrollments)
    define(:enroll_in_course, action: :enroll)
    define(:enroll_student_in_course, action: :enroll_student)
    define(:cancel_enrollment, action: :cancel)
    define(:complete_enrollment, action: :mark_completed)
  end

  actions do
    defaults([:read, :destroy])

    read :my_enrollments do
      description("当前学生的选课列表（仅自己的）")
      filter(expr(user_id == ^actor(:id)))
    end

    create :enroll do
      description("学生选课：课程须已发布，单课程一次")
      accept([:course_id])

      change(set_attribute(:user_id, actor(:id)))
      change({TcmEdu.Enrollment.Changes.EnsureCoursePublished, []})
    end

    create :enroll_student do
      description("教师/管理员为学生添加选课（已取消的选课会重新激活）")
      accept([:course_id, :user_id])

      # 重新添加已取消的学生时走 upsert，把 status 改回 active
      upsert?(true)
      upsert_identity(:unique_user_course)
      upsert_fields([:status, :enrolled_at])

      change(set_attribute(:status, :active))
      change(set_attribute(:enrolled_at, &DateTime.utc_now/0))
      change({TcmEdu.Enrollment.Changes.EnsureTeacherCanEnroll, []})
    end

    update :cancel do
      description("取消选课（本人或管理员）")
      accept([])
      change(set_attribute(:status, :cancelled))
    end

    update :mark_completed do
      description("标记学完（本人或管理员）")
      accept([])
      change(set_attribute(:status, :completed))
      change(set_attribute(:completed_at, &DateTime.utc_now/0))
    end

    action :overview, :map do
      description("学员首页统计：选课 / 完成课时 / 学习时长 / 连续天数 / 错题 / 未读通知")
      run(TcmEdu.Enrollment.Overview)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if(always())
    end

    # 读：管理员看所有；教师看自己课程的选课；学生看自己的
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(expr(course.teacher_id == ^actor(:id)))
      authorize_if(relates_to_actor_via(:user))
    end

    # 选课：仅学生（user_id 强制取 actor，防冒认）
    policy action(:enroll) do
      authorize_if(actor_attribute_equals(:role, :student))
    end

    # 教师/管理员代学生选课：属主校验交给
    # `TcmEdu.Enrollment.Changes.EnsureTeacherCanEnroll`（run 阶段可查库）
    policy action(:enroll_student) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action(:cancel) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(expr(course.teacher_id == ^actor(:id)))
      authorize_if(relates_to_actor_via(:user))
    end

    policy action(:mark_completed) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(relates_to_actor_via(:user))
    end

    # 首页统计是 generic action（无目标记录，不匹配 action_type(:read)），
    # 不加这条 policy 会因「无 policy 命中」默认 Forbidden。
    # 具体数字的属主过滤写在 TcmEdu.Enrollment.Overview 里。
    policy action(:overview) do
      authorize_if(actor_present())
    end

    policy action(:destroy) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end
  end
end
