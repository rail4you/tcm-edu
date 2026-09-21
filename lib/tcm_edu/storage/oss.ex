defmodule TcmEdu.Storage.OSS do
  @moduledoc """
  阿里云 OSS 客户端（`xingningshu` bucket）。

  使用 OSS 原生 REST API + v1 签名（HMAC-SHA1），通过 `Req` 发起请求。
  设计目标是接住 `MedicalImage` 生成的 24h 过期 URL，
  以及后续 AshStorage 上传（学生头像 / 课时附件 / 题库配图）。

  ## 凭证

  只从环境变量读取（仓库内不保存任何硬编码 key）：

    * `OSS_ACCESS_KEY_ID` / `OSS_ACCESS_KEY_SECRET` — 必填
    * `OSS_BUCKET` / `OSS_ENDPOINT` / `OSS_REGION` — 可选（有默认值）

  本地开发请写进仓库根目录 `.env`（已被 gitignore 忽略）或
  启动前 `export`，缺失时调用会直接 raise 提示。

  ## 用法

      iex> TcmEdu.Storage.OSS.upload_from_url(
      ...>   "https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/x/heart.png",
      ...>   "ai/heart.png"
      ...> )
      {:ok, "https://xingningshu.oss-cn-beijing.aliyuncs.com/ai/heart.png"}
  """

  require Logger

  @default_bucket "xingningshu"
  @default_endpoint "oss-cn-beijing.aliyuncs.com"
  @default_region "cn-beijing"

  @type upload_result :: {:ok, String.t()} | {:error, term()}

  @doc """
  把远程 URL 的文件下载下来并上传到 OSS。

  ## 参数

    * `remote_url` — 远程文件地址（如 DashScope 返回的图片 URL）
    * `key`        — OSS 对象 key（如 `"ai/{prompt_hash}.png"`），必须以 `/` 开头或不以 `/` 开头均可
    * `opts`       — `:content_type`、`:bucket`、`:prefix`

  ## 返回

    * `{:ok, public_url}` — OSS 上的公开访问 URL（bucket 内网/公网域名）
    * `{:error, :download_failed | :upload_failed | reason}`
  """
  def upload_from_url(remote_url, key, opts \\ []) do
    Logger.info("[OSS] download #{remote_url} → #{key}")

    case Req.get(remote_url, [receive_timeout: 60_000, retry: false] ++ TcmEdu.AI.req_options()) do
      {:ok, %{status: status, body: body, headers: resp_headers}} when status in 200..299 ->
        content_type =
          opts[:content_type] ||
            get_resp_content_type(resp_headers) ||
            guess_content_type(remote_url)

        upload_bytes(body, key, Keyword.put(opts, :content_type, content_type))

      {:ok, %{status: status}} ->
        {:error, {:download_failed, status}}

      {:error, reason} ->
        {:error, {:download_failed, reason}}
    end
  end

  @doc """
  把原始字节上传到 OSS。

  ## 参数

    * `bytes` — 二进制内容
    * `key`   — 对象 key（如 `"lessons/tenant/x.png"`，可带前缀）
    * `opts`  — `:content_type`、`:bucket`、`:acl`（默认 public-read）、`:prefix`

  ## 返回

    * `{:ok, public_url}` — OSS 公开访问 URL
    * `{:error, reason}` — 签名/网络/权限失败
  """
  @spec upload_bytes(binary(), String.t(), keyword()) :: upload_result()
  def upload_bytes(bytes, key, opts \\ []) do
    bucket = opts[:bucket] || bucket()
    content_type = opts[:content_type] || "application/octet-stream"

    url = "https://#{bucket}.#{endpoint()}/#{normalize_key(key)}"
    headers = sign_put_headers(key, Keyword.put(opts, :content_type, content_type))

    Logger.info("[OSS] PUT #{url} (#{byte_size(bytes)} bytes)")

    case Req.put(
           url,
           [body: bytes, headers: headers, receive_timeout: 60_000, retry: false] ++
             TcmEdu.AI.req_options()
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, public_url(bucket, key)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("[OSS] PUT failed #{status}: #{inspect(body)}")
        {:error, {:upload_failed, status, body}}

      {:error, reason} ->
        Logger.error("[OSS] PUT transport: #{inspect(reason)}")
        {:error, {:transport, reason}}
    end
  end

  @doc "返回对象的公开访问 URL（bucket 需公共读；私有 bucket 请用 `signed_url/2`）"
  @spec public_url(String.t(), String.t()) :: String.t()
  def public_url(bucket \\ bucket(), key) do
    "https://#{bucket}.#{endpoint()}/#{normalize_key(key)}"
  end

  @doc """
  生成对象预签名 URL（OSS v1，可客户端直接访问）。

  ## 参数

    * `key`  — 对象 key
    * `opts` — `:bucket`、`:expires_in`（秒，默认 3600）

  ## 返回

    * `{:ok, url}` — 带 `OSSAccessKeyId` / `Expires` / `Signature` 的 URL

  用于私有 bucket（默认），浏览器/`<img>` 可直接加载。
  """
  @spec signed_url(String.t(), keyword()) :: {:ok, String.t()}
  def signed_url(key, opts \\ []) do
    bucket = opts[:bucket] || bucket()
    expires_in = opts[:expires_in] || 3_600
    expires = DateTime.utc_now() |> DateTime.to_unix() |> Kernel.+(expires_in)

    verb = "GET"
    canonicalized_resource = "/#{bucket}/#{normalize_key(key)}"

    # OSS v1 带 Expires 的签名：Date 行直接放置顶时间
    string_to_sign = "#{verb}\n\n\n#{expires}\n#{canonicalized_resource}"

    signature =
      :crypto.mac(:hmac, :sha, access_key_secret(), string_to_sign)
      |> Base.encode64()
      |> URI.encode_www_form()

    url =
      "https://#{bucket}.#{endpoint()}/#{normalize_key(key)}" <>
        "?OSSAccessKeyId=#{access_key_id()}" <>
        "&Expires=#{expires}" <>
        "&Signature=#{signature}"

    {:ok, url}
  end

  @doc "OSS bucket（默认 `xingningshu`，可由 `OSS_BUCKET` 环境变量覆盖）"
  def bucket, do: System.get_env("OSS_BUCKET") || @default_bucket

  @doc "OSS endpoint 主机名（默认 `oss-cn-beijing.aliyuncs.com`）"
  def endpoint, do: System.get_env("OSS_ENDPOINT") || @default_endpoint

  @doc "OSS region（默认 `cn-beijing`）"
  def region, do: System.get_env("OSS_REGION") || @default_region

  @doc "Access Key ID（环境变量 `OSS_ACCESS_KEY_ID`，无默认值，缺失时 raise）"
  def access_key_id, do: System.get_env("OSS_ACCESS_KEY_ID") || raise_missing("OSS_ACCESS_KEY_ID")

  @doc "Access Key Secret（环境变量 `OSS_ACCESS_KEY_SECRET`，无默认值，缺失时 raise）"
  def access_key_secret,
    do: System.get_env("OSS_ACCESS_KEY_SECRET") || raise_missing("OSS_ACCESS_KEY_SECRET")

  defp raise_missing(var) do
    raise "#{var} 未配置：请写进仓库根目录 .env（gitignore 已忽略）或启动前 export"
  end

  @doc """
  删除 OSS 对象。

  返回 `:ok | {:error, term()}`。
  """
  @spec delete_object(String.t(), keyword()) :: :ok | {:error, term()}
  def delete_object(key, opts \\ []) do
    bucket = opts[:bucket] || bucket()
    url = "https://#{bucket}.#{endpoint()}/#{normalize_key(key)}"
    headers = sign_headers(key, "DELETE", "", opts)

    case Req.delete(
           url,
           [headers: headers, receive_timeout: 30_000, retry: false] ++ TcmEdu.AI.req_options()
         ) do
      {:ok, %{status: s}} when s in 200..299 ->
        :ok

      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.error("[OSS] DELETE failed #{status}: #{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  检查对象是否存在（HEAD）。

  返回 `{:ok, true | false} | {:error, term()}`。
  """
  @spec exists?(String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def exists?(key, opts \\ []) do
    bucket = opts[:bucket] || bucket()
    url = "https://#{bucket}.#{endpoint()}/#{normalize_key(key)}"
    headers = sign_headers(key, "HEAD", "", opts)

    case Req.head(
           url,
           [headers: headers, receive_timeout: 30_000, retry: false] ++ TcmEdu.AI.req_options()
         ) do
      {:ok, %{status: 200}} -> {:ok, true}
      {:ok, %{status: 404}} -> {:ok, false}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  HEAD：返回对象 ETag / Content-Length / content_type。

  AshStorage.Service.head/2 依赖此函数。
  """
  @spec head_object(String.t(), keyword()) ::
          {:ok,
           %{etag: String.t() | nil, content_md5: String.t() | nil, byte_size: integer() | nil}}
          | {:error, term()}
  def head_object(key, opts \\ []) do
    bucket = opts[:bucket] || bucket()
    url = "https://#{bucket}.#{endpoint()}/#{normalize_key(key)}"
    headers = sign_headers(key, "HEAD", "", opts)

    case Req.head(
           url,
           [headers: headers, receive_timeout: 30_000, retry: false] ++ TcmEdu.AI.req_options()
         ) do
      {:ok, %{status: 200, headers: h}} ->
        {:ok,
         %{
           etag: get_header(h, "etag"),
           content_md5: nil,
           byte_size: parse_int(get_header(h, "content-length"))
         }}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # OSS v1 签名：按 verb 拼 string-to-sign；content-md5 与 content-type
  # 在 PUT 签名中（其他 verb 传空字符串）
  @spec sign_headers(String.t(), String.t(), String.t(), keyword()) :: %{String.t() => String.t()}
  def sign_headers(key, verb, content_md5 \\ "", opts \\ []) do
    bucket = opts[:bucket] || bucket()
    content_type = opts[:content_type] || ""
    date = format_gmt_date(DateTime.utc_now())
    canonicalized_resource = "/#{bucket}/#{normalize_key(key)}"

    string_to_sign =
      "#{verb}\n#{content_md5}\n#{content_type}\n#{date}\n#{canonicalized_resource}"

    signature =
      :crypto.mac(:hmac, :sha, access_key_secret(), string_to_sign)
      |> Base.encode64()

    base = %{"Date" => date, "Authorization" => "OSS #{access_key_id()}:#{signature}"}

    if content_type == "" do
      base
    else
      Map.put(base, "Content-Type", content_type)
    end
  end

  defp get_header(headers, key) when is_map(headers) do
    case Map.get(headers, key) do
      nil -> nil
      [v | _] -> v
      v when is_binary(v) -> v
      _ -> nil
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  # ─── 签名（OSS v1 · HMAC-SHA1） ────────────────────────────

  @doc """
  生成 OSS v1 签名的 PUT 请求 headers（含 Date / Authorization）。

  暴露为公开函数便于单测与调试。
  """
  @spec sign_put_headers(String.t(), keyword()) :: %{String.t() => String.t()}
  def sign_put_headers(key, opts \\ []) do
    bucket = opts[:bucket] || bucket()
    content_type = opts[:content_type] || "application/octet-stream"
    date = format_gmt_date(DateTime.utc_now())
    canonicalized_resource = "/#{bucket}/#{normalize_key(key)}"
    string_to_sign = "PUT\n\n#{content_type}\n#{date}\n#{canonicalized_resource}"

    signature =
      :crypto.mac(:hmac, :sha, access_key_secret(), string_to_sign)
      |> Base.encode64()

    %{
      "Date" => date,
      "Content-Type" => content_type,
      "Authorization" => "OSS #{access_key_id()}:#{signature}"
    }
  end

  # ─── 私有 ─────────────────────────────────────────────────

  defp normalize_key(key) do
    key
    |> String.trim_leading("/")
    |> String.split("/", trim: false)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&URI.encode_www_form/1)
    |> Enum.join("/")
  end

  defp format_gmt_date(%DateTime{} = dt) do
    dt
    |> DateTime.to_unix()
    |> DateTime.from_unix!()
    |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
  end

  defp get_resp_content_type(headers) when is_map(headers) do
    headers
    |> Enum.find_value(fn
      {"content-type", v} when is_binary(v) ->
        v |> List.first() |> Kernel.||(v)

      _ ->
        nil
    end)
  end

  defp guess_content_type(url) do
    case Path.extname(URI.parse(url).path || "") |> String.downcase() do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".mp4" -> "video/mp4"
      ".pdf" -> "application/pdf"
      ".json" -> "application/json"
      _ -> "application/octet-stream"
    end
  end
end
