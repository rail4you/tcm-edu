defmodule TcmEdu.Courses.Chapter do
  @moduledoc """
  课程章节（租户域）。`sort_order` 决定同课程内的展示顺序。
  """

  use Ash.Resource,
    domain: TcmEdu.Courses,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource],
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("chapters")
    repo(TcmEdu.Repo)
  end

  typescript do
    type_name("Chapter")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :sort_order, :integer do
      default(0)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :course, TcmEdu.Courses.Course do
      allow_nil?(false)
      # public?: true → course_id 可读可过滤（编辑页按课程加载章节）
      public?(true)
    end

    has_many :lessons, TcmEdu.Courses.Lesson do
      destination_attribute(:chapter_id)
      sort(sort_order: :asc)
      # public?: true → 教师端编辑页可嵌套加载课时
      public?(true)
    end
  end

  code_interface do
    define(:list_chapters, action: :read)
    define(:create_chapter, action: :create)
    define(:update_chapter, action: :update)
    define(:delete_chapter, action: :destroy)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:title, :sort_order, :course_id])
    end

    update :update do
      require_atomic?(false)
      accept([:title, :sort_order])
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if(always())
    end

    # 章节目录随课程可见性：已发布课程的章节任何人可见（含匿名）
    policy action(:read) do
      authorize_if(expr(course.status == :published))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(expr(course.teacher_id == ^actor(:id)))
    end

    # 写操作：管理员，或该课程的作者教师
    policy action(:create) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action(:update) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(expr(course.teacher_id == ^actor(:id)))
    end

    policy action(:destroy) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(expr(course.teacher_id == ^actor(:id)))
    end
  end
end
