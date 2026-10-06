defmodule TcmEdu.Notification.MarkAllRead do
  @moduledoc """
  把当前登录用户的全部未读通知标记为已读 —— `POST
  /api/student/notifications/mark_all_read` 的实现。

  对应 `TcmEdu.Notification.Notification` 上的 generic action `:mark_all_read`。
  用 generic action 而非 `update`，是因为 AshJsonApi 的 `patch` 路由必须带
  `:id` 段（`Helpers.update_record/2` 走 `fetch_record_from_path/3`），
  而「全部已读」没有目标记录；`route :post` 只接受 generic action。

  属主过滤写死在查询里，内层 `:mark_read` 的 policy（`recipient_id ==
  ^actor(:id)`）再兜一层。
  """

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  @impl true
  def run(_input, _opts, %{actor: nil}), do: {:error, "未登录"}

  def run(_input, _opts, context) do
    %{actor: actor, tenant: tenant} = context

    unread =
      TcmEdu.Notification.Notification
      |> Ash.Query.filter(recipient_id == ^actor.id and is_nil(read_at))

    with {:ok, count} <- Ash.count(unread, actor: actor, tenant: tenant) do
      # 注意：Ash.bulk_update/4 返回的是裸 %Ash.BulkResult{}，不是 {:ok, …}
      unread
      |> Ash.bulk_update(:mark_read, %{}, actor: actor, tenant: tenant)
      |> case do
        %Ash.BulkResult{status: status, errors: errors}
        when status in [:success, :partial_success] and errors in [nil, []] ->
          {:ok, %{updated: count}}

        %Ash.BulkResult{errors: errors} ->
          {:error, List.first(List.wrap(errors)) || "mark_all_read failed"}

        {:error, error} ->
          {:error, error}

        other ->
          {:error, other}
      end
    end
  end
end
