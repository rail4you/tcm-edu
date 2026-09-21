defmodule TcmEdu.Courses.Course do
  @moduledoc """
  课程（租户域）。

  状态机：`:draft` → `:published` → `:archived`（可重新 `:published`）。
  发布前置校验（`publish` action）：至少 1 个章节且至少 1 个课时。

  多租户：`multitenancy :context`，查询/变更必须带 `tenant: "tenant_<slug>"`。
  """

  use Ash.Resource,
    domain: TcmEdu.Courses,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource],
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  multitenancy do
    strategy :context
  end

  postgres do
    table("courses")
    repo(TcmEdu.Repo)
  end

  typescript do
    type_name("Course")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :subtitle, :string do
      public?(true)
    end

    attribute :description, :string do
      public?(true)
    end

    attribute :cover_image_url, :string do
      public?(true)
    end

    attribute :tags, {:array, :string} do
      default([])
      public?(true)
    end

    attribute :level, :atom do
      default(:beginner)
      constraints(one_of: [:beginner, :intermediate, :advanced])
      public?(true)
    end

    attribute :status, :atom do
      default(:draft)
      constraints(one_of: [:draft, :published, :archived])
      public?(true)
    end

    attribute :price_cents, :integer do
      default(0)
      public?(true)
    end

    attribute :published_at, :utc_datetime do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :teacher, TcmEdu.Accounts.User do
      allow_nil?(false)

      # public?: true → teacher_id 可读可选（教师端按自己筛选、列表展示作者）
      public?(true)
    end

    belongs_to :category, TcmEdu.Courses.CourseCategory do
      allow_nil?(true)
      # public?: true → category_id 可读（编辑页回显分类）
      public?(true)
    end

    has_many :chapters, TcmEdu.Courses.Chapter do
      destination_attribute(:course_id)
      sort(sort_order: :asc)
      # public?: true → 教师端编辑页可嵌套加载章节/课时结构
      public?(true)
    end

    has_many :enrollments, TcmEdu.Enrollment.Enrollment do
      destination_attribute(:course_id)
    end
  end

  aggregates do
    # authorize? false：计数是公开的课程卡片信息，不应被 Lesson 的
    # “仅免费可见”策略过滤（否则匿名看到的课时数永远是免费课时数）。
    # 课时标题/内容仍受 Lesson read policy 保护。
    count :total_lessons, [:chapters, :lessons] do
      authorize?(false)
    end

    count :total_chapters, :chapters do
      authorize?(false)
    end

    sum :total_duration, [:chapters, :lessons], :duration_seconds do
      authorize?(false)
    end

    # 选课人数同样是公开卡片信息（Phase 7 补齐，依赖 Enrollment）
    count :total_students, :enrollments do
      filter(expr(status == :active))
      authorize?(false)
    end
  end

  calculations do
    # AshTypescript 只暴露 calculation（不暴露 aggregate），故用 calculation 镜像：
    # lesson_count 用 expr 内联聚合；duration_seconds 引用上面的 sum 聚合
    # （expr 的 sum 不支持嵌套路径，但 aggregate 支持）。
    calculate :lesson_count, :integer, expr(total_lessons) do
      public?(true)
    end

    calculate :chapter_count, :integer, expr(total_chapters) do
      public?(true)
    end

    calculate :duration_seconds, :decimal, expr(total_duration) do
      public?(true)
    end

    calculate :student_count, :integer, expr(total_students) do
      public?(true)
    end
  end

  code_interface do
    define(:list_courses, action: :read)
    define(:list_published_courses, action: :list_published)
    define(:list_teacher_courses, action: :list_by_teacher)
    define(:list_category_courses, action: :list_by_category)
    define(:get_course, action: :read, get_by: [:id])
    define(:create_course, action: :create_course)
    define(:update_course, action: :update)
    define(:publish_course, action: :publish)
    define(:archive_course, action: :archive)
    define(:delete_course, action: :destroy)
    define(:list_popular_courses, action: :list_popular)
  end

  actions do
    defaults([:read, :destroy])

    update :update do
      description("编辑课程资料（状态流转走 publish / archive）")
      require_atomic?(false)

      accept([
        :title,
        :subtitle,
        :description,
        :cover_image_url,
        :tags,
        :level,
        :price_cents,
        :category_id
      ])
    end

    read :list_published do
      description("学生端公开列表：仅已发布课程")
      filter(expr(status == :published))
    end

    read :list_by_teacher do
      description("某教师的全部课程（含草稿，供教师端管理）")
      argument(:teacher_id, :uuid, allow_nil?: false)
      filter(expr(teacher_id == ^arg(:teacher_id)))
    end

    read :list_by_category do
      description("某分类下的已发布课程（学生端筛选）")
      argument(:category_id, :uuid, allow_nil?: false)
      filter(expr(category_id == ^arg(:category_id) and status == :published))
    end

    read :list_popular do
      description("热门课程：已发布按选课人数倒序 Top 10（学生端首页）")
      filter(expr(status == :published))
      prepare(build(sort: [total_students: :desc], limit: 10))
    end

    create :create_course do
      description("教师/管理员创建课程（初始为草稿）")

      accept([
        :title,
        :subtitle,
        :description,
        :cover_image_url,
        :tags,
        :level,
        :price_cents,
        :teacher_id,
        :category_id
      ])
    end

    update :publish do
      description("发布课程：要求至少 1 章节 + 1 课时")
      require_atomic?(false)
      accept([])

      validate(fn changeset, _context ->
        course_id = changeset.data.id
        tenant = changeset.tenant

        with {:chapters, [_ | _]} <- {:chapters, list_chapters(course_id, tenant)},
             {:lessons, [_ | _]} <- {:lessons, list_lessons(course_id, tenant)} do
          :ok
        else
          {:chapters, _} -> {:error, field: :chapters, message: "至少需要 1 个章节"}
          {:lessons, _} -> {:error, field: :chapters, message: "至少需要 1 个课时"}
        end
      end)

      change(set_attribute(:status, :published))
      change(set_attribute(:published_at, &DateTime.utc_now/0))
    end

    update :archive do
      description("下架课程（数据保留，可重新发布）")
      accept([])
      change(set_attribute(:status, :archived))
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if(always())
    end

    # 已发布课程任何人可见（含匿名）；草稿仅教师/管理员或作者可见
    policy action_type(:read) do
      authorize_if(expr(status == :published))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(relates_to_actor_via(:teacher))
    end

    policy action(:create_course) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action(:update) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(relates_to_actor_via(:teacher))
    end

    policy action(:publish) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(relates_to_actor_via(:teacher))
    end

    policy action(:archive) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(relates_to_actor_via(:teacher))
    end

    policy action(:destroy) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(relates_to_actor_via(:teacher))
    end
  end

  # ── publish 校验用的内部查询（authorize?: false，纯结构检查） ──

  defp list_chapters(course_id, tenant) do
    case TcmEdu.Courses.Chapter
         |> Ash.Query.filter(course_id == ^course_id)
         |> Ash.read(tenant: tenant, authorize?: false) do
      {:ok, chapters} -> chapters
      _ -> []
    end
  end

  defp list_lessons(course_id, tenant) do
    case TcmEdu.Courses.Chapter
         |> Ash.Query.filter(course_id == ^course_id)
         |> Ash.Query.load(:lessons)
         |> Ash.read(tenant: tenant, authorize?: false) do
      {:ok, chapters} -> Enum.flat_map(chapters, & &1.lessons)
      _ -> []
    end
  end
end
