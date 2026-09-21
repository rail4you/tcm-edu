defmodule TcmEdu.System.AuditLog do
  @moduledoc """
  操作日志（public schema，跨租户）。

  记录关键管理操作（租户配置变更、用户角色变更、课程发布/下架、超管操作等），
  供合规审查与运维追踪。数据量大，建议后续在 `inserted_at` 建归档策略。

  ## 设计

    * `tenant`      — 操作发生的租户（可为 nil 表示系统级操作）
    * `actor_id`    — 操作人
    * `action`      — 动作，如 `course.publish` / `organization.suspend`
    * `resource_type` / `resource_id` — 目标对象
    * `changes`     — `%{before: ..., after: ...}` 差异（可空）
  """

  use Ash.Resource,
    domain: TcmEdu.System,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table("audit_logs")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :tenant, :string do
      public?(true)
      description("操作发生的租户 schema 名")
    end

    attribute :actor_id, :uuid do
      public?(true)
    end

    attribute :action, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :resource_type, :string do
      public?(true)
    end

    attribute :resource_id, :uuid do
      public?(true)
    end

    attribute :changes, :map do
      default(%{})
      public?(true)
    end

    attribute :ip, :string do
      public?(true)
    end

    attribute :user_agent, :string do
      public?(true)
    end

    attribute :success, :boolean do
      default(true)
      public?(true)
    end

    create_timestamp(:inserted_at)
  end

  code_interface do
    define(:list_audit_logs, action: :read)
    define(:get_audit_log, action: :read, get_by: [:id])
    define(:record_audit_log, action: :record)
  end

  actions do
    defaults([:read])

    create :record do
      description("写入一条审计日志（多为中间层/回调自动调用）")

      accept([
        :tenant,
        :actor_id,
        :action,
        :resource_type,
        :resource_id,
        :changes,
        :ip,
        :user_agent,
        :success
      ])
    end

    read :filtered do
      description("带筛选的日志查询（超管/管理员）")
      argument(:tenant, :string, allow_nil?: true)
      argument(:action, :string, allow_nil?: true)
      argument(:actor_id, :uuid, allow_nil?: true)

      filter(
        expr(
          (is_nil(^arg(:tenant)) or tenant == ^arg(:tenant)) and
            (is_nil(^arg(:action)) or action == ^arg(:action)) and
            (is_nil(^arg(:actor_id)) or actor_id == ^arg(:actor_id))
        )
      )
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
    end

    policy action_type(:create) do
      authorize_if(actor_present())
    end
  end
end
