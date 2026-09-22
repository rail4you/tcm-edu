defmodule TcmEdu.Mdt.Case do
  @moduledoc """
  多学科会诊病例档案（租户域）。

  教师在 MDT 栏目创建会诊病例：填写患者主诉与病史、可参与科室角色列表
  （如内科/外科/影像/检验/护理），以及会诊期望达到的共同诊断/方案方向。

  `departments` 是科室角色名单（多个学员分别扮演其中一个）。`expected_conclusion`
  用于教师对照本次会诊是否正确收敛。

  多租户：`multitenancy :context`。
  """

  use Ash.Resource,
    domain: TcmEdu.Mdt,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("mdt_cases")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
      description("会诊病例名称")
    end

    attribute :scenario_title, :string do
      public?(true)
    end

    attribute :profile, :map do
      default(%{})
      public?(true)
      description("患者基础信息 JSON")
    end

    attribute :complaint, :string do
      allow_nil?(false)
      public?(true)
      description("患者主诉")
    end

    attribute :history, :string do
      public?(true)
      description("现病史/既往史/查体/辅助检查背景")
    end

    attribute :departments, {:array, :string} do
      default([])
      public?(true)
      description("可参与科室角色列表（如：内科、外科、影像科…）")
    end

    attribute :expected_conclusion, :string do
      public?(true)
      description("会诊期望收敛的诊断方向（供教师对照）")
    end

    attribute :status, :atom do
      default(:draft)
      constraints(one_of: [:draft, :published, :archived])
      public?(true)
    end

    attribute :created_by_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :created_by_email, :string do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :created_by, TcmEdu.Accounts.User do
      source_attribute(:created_by_id)
      destination_attribute(:id)
      define_attribute?(false)
      public?(true)
    end

    has_many :rooms, TcmEdu.Mdt.Room do
      destination_attribute(:case_id)
      public?(true)
    end
  end

  code_interface do
    define(:list_cases, action: :read)
    define(:get_case, action: :read, get_by: [:id])
    define(:create_case, action: :create)
    define(:publish_case, action: :publish)
    define(:archive_case, action: :archive)
    define(:delete_case, action: :destroy)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :name,
        :scenario_title,
        :profile,
        :complaint,
        :history,
        :departments,
        :expected_conclusion,
        :status,
        :created_by_id,
        :created_by_email
      ])

      validate(present([:complaint]))
    end

    update :update do
      primary?(true)

      accept([
        :name,
        :scenario_title,
        :profile,
        :complaint,
        :history,
        :departments,
        :expected_conclusion,
        :status
      ])
    end

    update :publish do
      require_atomic?(false)
      accept([])
      change(set_attribute(:status, :published))
    end

    update :archive do
      require_atomic?(false)
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

    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(actor_attribute_equals(:role, :student))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end
  end
end
