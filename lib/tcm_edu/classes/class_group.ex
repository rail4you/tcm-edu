defmodule TcmEdu.Classes.ClassGroup do
  @moduledoc """
  班级（租户域）：一组学生的聚合。

  多租户：`multitenancy :context`，查询/变更必须带 `tenant: "tenant_<slug>"`。

  学生通过 `TcmEdu.Accounts.User.class_group_id` 归属班级；同一租户内
  班级名唯一（`unique_name_per_tenant`）。
  """

  use Ash.Resource,
    domain: TcmEdu.Classes,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("class_groups")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_name_per_tenant, [:name])
  end

  code_interface do
    define(:list_class_groups, action: :read)
    define(:get_class_group_by_id, action: :read, get_by: [:id])
    define(:create_class_group, action: :create)
    define(:update_class_group, action: :update)
    define(:destroy_class_group, action: :destroy)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:name])
    end

    update :update do
      require_atomic?(false)
      accept([:name])
    end
  end

  policies do
    # super_admin 跨租户全放行
    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if(always())
    end

    # 读：管理员 / 教师可见本租户班级
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    # 写：仅租户管理员
    policy action_type([:create, :update, :destroy]) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
    end
  end
end
