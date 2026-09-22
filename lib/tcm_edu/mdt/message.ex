defmodule TcmEdu.Mdt.Message do
  @moduledoc """
  会诊室消息（租户域）。

  `role` 标识发言人来源：`patient`（AI 扮演的患者）/ `dept:<科室>`（AI 扮演的
  其他科室专家）/ `student:<科室>`（学员本人）/ `system`（AI 会诊主持引导）。

  `kind` 便于按消息类型渲染：`chat`（普通发言）/ `opinion`（某科意见）。
  """

  use Ash.Resource,
    domain: TcmEdu.Mdt,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("mdt_messages")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :role, :string do
      allow_nil?(false)
      public?(true)
      description("发言角色：patient / dept:外科学 / student:内科学")
    end

    attribute :content, :string do
      allow_nil?(false)
      public?(true)
      constraints(min_length: 1, max_length: 5000)
    end

    attribute :kind, :string do
      default("chat")
      public?(true)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :room, TcmEdu.Mdt.Room do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :author, TcmEdu.Accounts.User do
      public?(true)
      description("学员发言时记录作者；AI/患者发言为空")
    end
  end

  code_interface do
    define(:list_messages, action: :read)
    define(:create_message, action: :create)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:room_id, :role, :content, :kind, :author_id])
      validate(present([:room_id, :role, :content]))
      validate(string_length(:content, min: 1, max: 5000))
    end

    read :for_room do
      argument(:room_id, :uuid, allow_nil?: false)
      filter(expr(room_id == ^arg(:room_id)))
      prepare(build(sort: [inserted_at: :asc]))
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
      authorize_if(expr(exists(room, participants.user_id == ^actor(:id))))
      authorize_if(expr(room.owner_id == ^actor(:id)))
    end

    policy action_type(:create) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(actor_attribute_equals(:role, :student))
    end
  end
end