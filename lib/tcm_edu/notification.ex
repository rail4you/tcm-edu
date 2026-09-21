defmodule TcmEdu.Notification do
  @moduledoc """
  通知域（租户域）：站内信。

  资源：
    * `TcmEdu.Notification.Notification` — 站内通知（未读/已读）

  多租户：`multitenancy :context`。教师/管理员通过 Oban worker 异步推送
  （见 `Notifications.Deliver`），避免在业务 action 内同步阻塞。
  """

  use Ash.Domain,
    otp_app: :tcm_edu,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource TcmEdu.Notification.Notification do
      rpc_action(:list_notifications, :read)
      rpc_action(:get_notification, :read, get_by: [:id])
      rpc_action(:create_notification, :notify)
      rpc_action(:mark_read, :mark_read)
      rpc_action(:mark_all_read, :mark_all_read)
    end
  end

  resources do
    resource TcmEdu.Notification.Notification
  end
end
