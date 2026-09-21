defmodule TcmEduWeb.CourseCover do
  @moduledoc """
  课程封面上传共享逻辑（AshStorage `has_one_attached :cover_image`，OSS 后端）。

  教师端新建 / 编辑页通过 LiveView `allow_upload` 暂存图片，保存时
  `consume_cover/3` 落盘到 OSS 并关联到课程；AI 配图页走
  `attach_from_url/4` 把已归档的 OSS 图片直接设为封面。
  """

  import Phoenix.LiveView,
    only: [allow_upload: 3, consume_uploaded_entries: 3, disallow_upload: 2]

  alias TcmEdu.Courses.Course

  @accept ~w(.jpg .jpeg .png .webp)
  @max_file_size 5_000_000

  @doc "LiveView 封面上传配置（单文件、图片、5MB）。"
  def allow_cover_upload(socket) do
    allow_upload(socket, :cover,
      accept: @accept,
      max_entries: 1,
      max_file_size: @max_file_size
    )
  end

  @doc """
  消费暂存的封面并关联到课程。返回 `:no_entry`（未选文件）、
  `{:ok, url}` 或 `{:error, message}`。
  """
  def consume_cover(socket, %Course{} = course, teacher) do
    # consume_uploaded_entries 的 callback 须返 {:ok, value}，LV 会拆掉这层
    # （channel 上传与 external 上传最终都只剩 value），故下面直接匹配 value。
    results =
      consume_uploaded_entries(socket, :cover, fn %{path: path}, entry ->
        result =
          with {:ok, data} <- File.read(path) do
            case AshStorage.Operations.attach(course, :cover_image, data,
                   filename: entry.client_name,
                   content_type: entry.client_type || "application/octet-stream",
                   actor: teacher.actor,
                   tenant: teacher.tenant
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
      [{:ok, %{blob: _}} | _] ->
        loaded = Ash.load!(course, :cover_image_url, actor: teacher.actor, tenant: teacher.tenant)
        {:ok, loaded.cover_image_url}

      [{:error, message} | _] ->
        {:error, message}

      [] ->
        :no_entry
    end
  end

  @doc "移除课程封面（删除关联、blob 记录与 OSS 文件）。"
  def remove_cover(%Course{} = course, teacher) do
    case AshStorage.Operations.purge(course, :cover_image,
           actor: teacher.actor,
           tenant: teacher.tenant
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, format_reason(reason)}
    end
  end

  @doc "把一个已在线的图片 URL 下载后设为课程封面（AI 配图页用）。"
  def attach_from_url(%Course{} = course, teacher, url, filename \\ "ai-cover.png") do
    with {:ok, %{status: 200, body: body, headers: headers}} <-
           Req.get(url, TcmEdu.AI.req_options()),
         data <- IO.iodata_to_binary(body) do
      content_type =
        case List.keyfind(headers, "content-type", 0) do
          {_, ct} -> hd(String.split(ct, ";"))
          nil -> "image/png"
        end

      case AshStorage.Operations.attach(course, :cover_image, data,
             filename: filename,
             content_type: content_type,
             actor: teacher.actor,
             tenant: teacher.tenant
           ) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, format_reason(reason)}
      end
    else
      {:ok, %{status: status}} -> {:error, "图片下载失败（HTTP #{status}）"}
      {:error, reason} -> {:error, format_reason(reason)}
    end
  end

  @doc "清空暂存的封面（开关弹窗时调用，避免残留 entries 串到别的课程）。"
  def reset_cover_upload(socket) do
    socket
    |> disallow_upload(:cover)
    |> allow_cover_upload()
  end

  @doc "上传错误的中文文案（`upload_errors/2` 返回的 atom → 人话）。"
  def error_text(:too_large), do: "文件超过 5MB，请压缩后重试"
  def error_text(:not_accepted), do: "仅支持 JPG / PNG / WebP 图片"
  def error_text(:too_many_files), do: "一次只能上传一张封面"
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
