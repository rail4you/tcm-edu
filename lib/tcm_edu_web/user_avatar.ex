defmodule TcmEduWeb.UserAvatar do
  @moduledoc """
  用户头像上传共享逻辑（AshStorage `has_one_attached :avatar`，OSS 后端）。

  管理端「编辑用户」弹窗与账户设置页通过 LiveView `allow_upload` 暂存图片，
  保存时 `consume_avatar/3` 落盘并关联到用户；`remove_avatar/2` 清除头像。
  """

  import Phoenix.LiveView,
    only: [allow_upload: 3, consume_uploaded_entries: 3, disallow_upload: 2]

  alias TcmEdu.Accounts.User

  @accept ~w(.jpg .jpeg .png .webp)
  @max_file_size 5_000_000

  @doc "LiveView 头像上传配置（单文件、图片、5MB）。"
  def allow_avatar_upload(socket) do
    allow_upload(socket, :avatar,
      accept: @accept,
      max_entries: 1,
      max_file_size: @max_file_size
    )
  end

  @doc "清空暂存的头像（开关弹窗时调用，避免残留 entries 串到别的用户）。"
  def reset_avatar_upload(socket) do
    socket
    |> disallow_upload(:avatar)
    |> allow_avatar_upload()
  end

  @doc """
  消费暂存的头像并关联到用户。返回 `:no_entry`（未选文件）、`:ok`
  或 `{:error, message}`。
  """
  def consume_avatar(socket, %User{} = user, admin) do
    # consume_uploaded_entries 的 callback 须返 {:ok, value}，LV 会拆掉这层。
    results =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
        result =
          with {:ok, data} <- File.read(path) do
            case AshStorage.Operations.attach(user, :avatar, data,
                   filename: entry.client_name,
                   content_type: entry.client_type || "application/octet-stream",
                   actor: admin.actor,
                   tenant: admin.tenant
                 ) do
              {:ok, _} = ok -> ok
              {:error, reason} -> {:error, format_reason(reason)}
            end
          else
            {:error, reason} -> {:error, "读取上传文件失败：#{inspect(reason)}"}
          end

        {:ok, result}
      end)

    case results do
      [{:ok, %{blob: _}} | _] -> :ok
      [{:error, message} | _] -> {:error, message}
      [] -> :no_entry
    end
  rescue
    error -> {:error, format_reason(error)}
  end

  @doc "移除用户头像（删除关联、blob 记录与 OSS 文件）。"
  def remove_avatar(%User{} = user, admin) do
    case AshStorage.Operations.purge(user, :avatar,
           actor: admin.actor,
           tenant: admin.tenant
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, format_reason(reason)}
    end
  rescue
    error -> {:error, format_reason(error)}
  end

  @doc "上传错误的中文文案（`upload_errors/2` 返回的 atom → 人话）。"
  def error_text(:too_large), do: "文件超过 5MB，请压缩后重试"
  def error_text(:not_accepted), do: "仅支持 JPG / PNG / WebP 图片"
  def error_text(:too_many_files), do: "一次只能上传一张头像"
  def error_text(_), do: "文件上传失败，请重试"

  defp format_reason(%Ash.Error.Forbidden{}), do: "没有权限执行该操作"

  defp format_reason(%Ash.Error.Invalid{} = error) do
    error.errors
    |> Enum.map(&Exception.message/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("；")
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
