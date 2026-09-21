defmodule TcmEdu.Courses.Lesson do
  @moduledoc """
  课时（租户域），归属章节。

  * `:video`   — `content_url` 为视频地址，`duration_seconds` 为时长
  * `:article` — `content_text` 为正文（markdown）
  * `:pdf`     — `content_url` 为 PDF 地址
  * `is_free_preview` 为 true 的课时可匿名试看

  Phase 6 的读策略：免费课时公开；其余需登录（Phase 7 收紧为“已选课”）。
  """

  use Ash.Resource,
    domain: TcmEdu.Courses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("lessons")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :content_type, :atom do
      default(:video)
      constraints(one_of: [:video, :article, :pdf])
      public?(true)
    end

    attribute :content_url, :string do
      public?(true)
    end

    attribute :content_text, :string do
      public?(true)
    end

    attribute :duration_seconds, :integer do
      default(0)
      public?(true)
    end

    attribute :sort_order, :integer do
      default(0)
      public?(true)
    end

    attribute :is_free_preview, :boolean do
      default(false)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :chapter, TcmEdu.Courses.Chapter do
      allow_nil?(false)
      # public?: true → chapter_id 可读可过滤（编辑页按章节加载课时）
      public?(true)
    end
  end

  code_interface do
    define(:list_lessons, action: :read)
    define(:create_lesson, action: :create)
    define(:update_lesson, action: :update)
    define(:delete_lesson, action: :destroy)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([
        :title,
        :content_type,
        :content_url,
        :content_text,
        :duration_seconds,
        :sort_order,
        :is_free_preview,
        :chapter_id
      ])
    end

    update :update do
      require_atomic?(false)

      accept([
        :title,
        :content_type,
        :content_url,
        :content_text,
        :duration_seconds,
        :sort_order,
        :is_free_preview
      ])
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if(always())
    end

    policy action(:read) do
      authorize_if(expr(is_free_preview == true))
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      # Phase 6：登录即可读非免费课时；Phase 7 收紧为仅已选课学生
      authorize_if(actor_present())
    end

    policy action(:create) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action(:update) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(expr(chapter.course.teacher_id == ^actor(:id)))
    end

    policy action(:destroy) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(expr(chapter.course.teacher_id == ^actor(:id)))
    end
  end
end
