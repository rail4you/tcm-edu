defmodule TcmEdu.SimulatedPatient.Message do
  @moduledoc """
  模拟诊疗会话中的一条消息（租户域）。

    * `role` — `student` / `patient`（AI 扮演的病人）
    * `content` — 文本内容
    * `turn_index` — 在会话内的轮次编号（0-based，仅学生消息递增）
    * `metadata` — 附加信息（如病人主动揭开的病史片段）

  多租户：`multitenancy :context`。
  """

  use Ash.Resource,
    domain: TcmEdu.SimulatedPatient,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :context
  end

  postgres do
    table("simulated_patient_messages")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :role, :string do
      allow_nil?(false)
      public?(true)
      constraints(match: ~r/^(student|patient)$/)
    end

    attribute :content, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :turn_index, :integer do
      default(0)
      public?(true)
    end

    attribute :metadata, :map do
      default(%{})
      public?(true)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :session, TcmEdu.SimulatedPatient.Session do
      allow_nil?(false)
      public?(true)
    end
  end

  code_interface do
    define(:list_messages, action: :read)
    define(:get_message, action: :read, get_by: [:id])
    define(:create_message, action: :create)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)

      accept([:session_id, :role, :content, :turn_index, :metadata])

      validate(string_length(:content, min: 1, max: 8000))
    end

    read :for_session do
      argument(:session_id, :uuid, allow_nil?: false)
      filter(expr(session_id == ^arg(:session_id)))
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
      authorize_if(expr(exists(session, student_id == ^actor(:id))))
    end

    # 写入由 LiveView / worker 在带着 student actor 时创建（chat 路径），
    # 教师端查看场景也需要能 read。destroy 仅本人 / 教师 / admin。
    policy action_type(:create) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(expr(exists(session, student_id == ^actor(:id))))
    end

    policy action_type(:destroy) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end
  end
end
