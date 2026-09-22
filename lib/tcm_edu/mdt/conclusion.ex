defmodule TcmEdu.Mdt.Conclusion do
  @moduledoc """
  会诊汇总结论（租户域）。

  由 `AI.MdtFacilitator.summarize/1` 在会诊结束时根据全部消息生成，包含共同诊断、
  各科采纳意见与最终处置/治疗方案。
  """

  use Ash.Resource,
    domain: TcmEdu.Mdt,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("mdt_conclusions")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :primary_diagnosis, :string do
      public?(true)
      description("会诊共同诊断")
    end

    attribute :differential, :string do
      public?(true)
      description("需鉴别的疾病")
    end

    attribute :treatment, :string do
      public?(true)
      description("最终处置/治疗方案")
    end

    attribute :roles_considered, {:array, :string} do
      default([])
      public?(true)
      description("最终采纳了哪些科室意见")
    end

    attribute :summary, :string do
      public?(true)
      description("总结评语")
    end

    attribute :model, :string do
      public?(true)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :room, TcmEdu.Mdt.Room do
      allow_nil?(false)
      public?(true)
    end
  end

  code_interface do
    define(:create_conclusion, action: :create)
    define(:get_conclusion, action: :read, get_by: [:id])
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)

      accept([
        :room_id,
        :primary_diagnosis,
        :differential,
        :treatment,
        :roles_considered,
        :summary,
        :model
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

    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(expr(room.owner_id == ^actor(:id)))
    end

    policy action_type(:create) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end
  end
end