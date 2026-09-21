defmodule TcmEdu.Storage.OSS.Service do
  @moduledoc """
  AshStorage.Service 实现：所有 AshStorage 上传都走 `xingningshu` OSS bucket。

  用法（`config/config.exs`）：

      config :tcm_edu,
        storage: [
          service: {TcmEdu.Storage.OSS.Service, []}
        ]

  接受 service_opts：
    * `:bucket` — 默认 `TcmEdu.Storage.OSS.bucket/0`（`xingningshu`）
    * `:prefix` — key 前缀（默认 `xingningshu/<tenant_or_avatar>/`），实际由
                   AshStorage 的 key 直接传，这里不强制加
    * `:decode_body` — `download/2` 是否解码（默认 `false`，保留原始字节）
    * `:expires_in` — `url/2` 预签名有效期（秒，默认 `3600`）

  注意：bucket 默认私有 ACL，因此 `url/2` 返回**预签名 URL**（与
  AI 配图归档链路一致），而不是公开 URL。
  """

  @behaviour AshStorage.Service

  alias AshStorage.Service.Context

  @impl true
  def service_opts_fields do
    [
      bucket: [type: :string],
      prefix: [type: :string],
      decode_body: [type: :boolean],
      expires_in: [type: :pos_integer]
    ]
  end

  @impl true
  def upload(key, data, %Context{} = ctx) do
    opts = [
      bucket: ctx.service_opts[:bucket],
      content_type: ctx.content_type
    ]

    case TcmEdu.Storage.OSS.upload_bytes(IO.iodata_to_binary(data), key, opts) do
      {:ok, _url} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def download(key, %Context{} = ctx) do
    bucket = ctx.service_opts[:bucket] || TcmEdu.Storage.OSS.bucket()
    url = TcmEdu.Storage.OSS.public_url(bucket, key)

    decode_body? = Keyword.get(ctx.service_opts, :decode_body, false)

    case Req.get(url, [decode_body: decode_body?] ++ TcmEdu.AI.req_options()) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} -> {:ok, IO.iodata_to_binary(body)}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(key, %Context{} = ctx) do
    TcmEdu.Storage.OSS.delete_object(key, bucket: ctx.service_opts[:bucket])
  end

  @impl true
  def exists?(key, %Context{} = ctx) do
    TcmEdu.Storage.OSS.exists?(key, bucket: ctx.service_opts[:bucket])
  end

  @impl true
  def url(key, %Context{} = ctx) do
    bucket = ctx.service_opts[:bucket] || TcmEdu.Storage.OSS.bucket()
    expires_in = ctx.service_opts[:expires_in] || 3_600

    # bucket 私有 ACL：公开 URL 会 403，必须返回预签名 URL
    # （`signed_url/2` 为纯函数，按 spec 总是成功）。
    {:ok, url} = TcmEdu.Storage.OSS.signed_url(key, bucket: bucket, expires_in: expires_in)
    url
  end

  @impl true
  def head(key, %Context{} = ctx) do
    TcmEdu.Storage.OSS.head_object(key, bucket: ctx.service_opts[:bucket])
  end
end
