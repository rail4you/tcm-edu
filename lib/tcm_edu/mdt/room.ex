defmodule TcmEdu.Mdt.Room do
  @moduledoc """
  一次多学科会诊室（租户域）。

  关联会诊病例，有一个患者和若干参与者（学生扮演的科室医生）。AI 在会诊中
  扮演患者，并按其它科室的立场补充发言。

  `status`：`:open`（进行中）/ `:concluded`（已汇总）/ `:abandoned`。
  """

  use Ash.Resource,
    domain: TcmEdu.Mdt,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("mdt_rooms")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :status, :atom do
      default(:open)
      constraints(one_of: [:open, :concluded, :abandoned])
      public?(true)
    end

    attribute :case_snapshot, :map do
      default(%{})
      public?(true)
      description("创建时从 Mdt.Case 拷贝的快照（主诉/病史/科室/期望方向）")
    end

    attribute :concluded_at, :utc_datetime do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :case, TcmEdu.Mdt.Case do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :owner, TcmEdu.Accounts.User do
      allow_nil?(false)
      public?(true)
      description("发起这场会诊的学生/教师")
    end

    has_many :participants, TcmEdu.Mdt.Participant do
      destination_attribute(:room_id)
      public?(true)
    end

    has_many :messages, TcmEdu.Mdt.Message do
      destination_attribute(:room_id)
      public?(true)
    end

    has_one :conclusion, TcmEdu.Mdt.Conclusion do
      destination_attribute(:room_id)
      public?(true)
    end
  end

  aggregates do
    count(:participant_count, :participants)
    count(:message_count, :messages)
  end

  code_interface do
    define(:list_rooms, action: :read)
    define(:get_room, action: :read, get_by: [:id])
    define(:create_room, action: :create)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:case_id, :owner_id, :status, :case_snapshot])
      validate(present([:case_snapshot]))
    end

    update :update do
      primary?(true)
      accept([:status, :concluded_at])
    end

    update :conclude do
      require_atomic?(false)
      accept([])
      change(set_attribute(:status, :concluded))
      change(set_attribute(:concluded_at, &DateTime.utc_now/0))
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
      authorize_if(expr(exists(participants, user_id == ^actor(:id))))
      authorize_if(expr(owner_id == ^actor(:id)))
    end

    policy action_type(:create) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(actor_attribute_equals(:role, :student))
    end

    policy action_type([:update, :destroy]) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(expr(owner_id == ^actor(:id)))
    end
  end
end
