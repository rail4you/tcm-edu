defmodule TcmEdu.Notification.Notification do
  @moduledoc """
  站内通知（租户域）。

  * `recipient_id` — 接收人（User）
  * `type`         — 通知类型
  * `title` / `body` — 展示内容
  * `payload`      — 结构化数据（如课程 id、跳转路由）
  * `read_at`      — 已读时间（nil = 未读）

  读取策略：仅本人可读；写大多来自 Oban worker（`Notifications.Deliver`）。
  """

  use Ash.Resource,
    domain: TcmEdu.Notification,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource],
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query
  import Ash.Expr

  multitenancy do
    strategy :context
  end

  postgres do
    table("notifications")
    repo(TcmEdu.Repo)
  end

  typescript do
    type_name("Notification")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :actor_id, :uuid do
      public?(true)
      description("触发该通知的用户（如发布课程的教师）")
    end

    attribute :type, :atom do
      default(:system)

      constraints(
        one_of: [
          :system,
          :enrollment,
          :course_published,
          :progress,
          :quiz_graded,
          :ai_lesson
        ]
      )

      public?(true)
    end

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :body, :string do
      public?(true)
    end

    attribute :payload, :map do
      default(%{})
      public?(true)
      description("结构化数据，如 %{course_id: ..., route: \"/course/x\"}")
    end

    attribute :read_at, :utc_datetime do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :recipient, TcmEdu.Accounts.User do
      allow_nil?(false)
      public?(true)
    end
  end

  calculations do
    calculate :is_read, :boolean, expr(not is_nil(read_at)) do
      public?(true)
    end
  end

  code_interface do
    define(:list_notifications, action: :read)
    define(:get_notification, action: :read, get_by: [:id])
    define(:create_notification, action: :notify)
    define(:mark_read, action: :mark_read)
    define(:mark_all_read, action: :mark_all_read)
    define(:unread_count, action: :unread_count)
  end

  actions do
    defaults([:read, :destroy])

    create :notify do
      description("创建通知（多由 Oban worker 调用）")
      accept([:recipient_id, :actor_id, :type, :title, :body, :payload])
    end

    update :mark_read do
      description("将一条通知标记为已读")
      accept([])
      change(set_attribute(:read_at, &DateTime.utc_now/0))
    end

    update :mark_all_read do
      description("将当前登录用户的全部通知标记为已读")
      require_atomic?(false)
      accept([])

      change(fn changeset, context ->
        user_id = context.actor.id
        Ash.Changeset.filter(changeset, expr(recipient_id == ^user_id and is_nil(read_at)))
      end)
    end

    read :unread_count do
      description("当前用户的未读数（返回单条记录，用于顶栏红点）")
      filter(expr(recipient_id == ^actor(:id) and is_nil(read_at)))
      prepare(build(load: []))
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
      authorize_if(expr(recipient_id == ^actor(:id)))
    end

    policy action_type([:create, :destroy]) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end

    policy action([:mark_read, :mark_all_read]) do
      authorize_if(expr(recipient_id == ^actor(:id)))
    end
  end
end
