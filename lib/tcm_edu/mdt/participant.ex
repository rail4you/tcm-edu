defmodule TcmEdu.Mdt.Participant do
  @moduledoc """
  会诊室参与者（租户域）：一个学生扮演某个科室角色。

  `department` 是科室角色标识（如「内科」），`display_name` 用于会诊中展示。
  """

  use Ash.Resource,
    domain: TcmEdu.Mdt,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("mdt_participants")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :department, :string do
      allow_nil?(false)
      public?(true)
      description("该学员扮演的科室角色")
    end

    attribute :display_name, :string do
      public?(true)
      description("会诊中的展示名（如：内科-张同学）")
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :room, TcmEdu.Mdt.Room do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :user, TcmEdu.Accounts.User do
      allow_nil?(false)
      public?(true)
    end
  end

  code_interface do
    define(:list_participants, action: :read)
    define(:create_participant, action: :create)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:room_id, :user_id, :department, :display_name])
      validate(present([:room_id, :user_id, :department]))
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(expr(user_id == ^actor(:id)))
    end

    policy action_type(:create) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(actor_attribute_equals(:role, :student))
    end
  end
end
