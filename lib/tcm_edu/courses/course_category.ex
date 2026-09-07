defmodule TcmEdu.Courses.CourseCategory do
  @moduledoc """
  课程分类（租户域，两级）。

  * `parent_id == nil` → 一级分类（如“中医基础”）
  * `parent_id != nil` → 二级分类（如“中医基础 / 藏象学说”）
  * `slug` 在同一租户内唯一
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
    table "course_categories"
    repo TcmEdu.Repo
  end

  typescript do
    type_name "CourseCategory"
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
      constraints match: ~r/^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$/
    end

    attribute :icon, :string do
      public? true
    end

    attribute :sort_order, :integer do
      default 0
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_slug_per_tenant, [:slug]
  end

  relationships do
    belongs_to :parent, __MODULE__ do
      allow_nil? true
    end

    has_many :children, __MODULE__ do
      destination_attribute :parent_id
      sort sort_order: :asc
    end

    has_many :courses, TcmEdu.Courses.Course do
      destination_attribute :category_id
    end
  end

  code_interface do
    define :list_categories, action: :read
    define :create_category, action: :create
    define :update_category, action: :update
    define :delete_category, action: :destroy
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [:name, :slug, :icon, :sort_order, :parent_id]
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if always()
    end

    # 分类是公开浏览信息（含匿名学生端）
    policy action(:read) do
      authorize_if always()
    end

    policy action(:create) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end

    policy action(:update) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end

    policy action(:destroy) do
      authorize_if actor_attribute_equals(:role, :tenant_admin)
    end
  end
end
