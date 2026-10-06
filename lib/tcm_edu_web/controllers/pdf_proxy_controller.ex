defmodule TcmEduWeb.PdfProxyController do
  @moduledoc """
  `/pdfjs/doc?u=<url>` — 给自托管 pdf.js viewer 用的同源转发端点。

  viewer 跑在本站源下，而 PDF 常在别的域（演示占位数据在公共站点，
  正式内容在 OSS）。直接让 viewer 跨源去取，要么被上游 CORS 挡住
  （`www.w3.org` 就不发 `access-control-allow-origin`），要么依赖上游
  配置。改成后端转发后，viewer 取到的是同源资源，浏览器根本不会走
  CORS 预检。

  为避免变成开放代理（SSRF），只转发 `:pdf_proxy_hosts` 白名单里
  的主机——白名单还会自动带上 OSS 的 endpoint/bucket 域名。
  """

  use TcmEduWeb, :controller

  @max_redirects 3
  @max_bytes 128 * 1024 * 1024

  def show(conn, %{"u" => url}) do
    with {:ok, uri} <- parse_url(url),
         :ok <- ensure_allowed(uri),
         {:ok, upstream} <- fetch(uri, range(conn), @max_redirects) do
      conn
      |> maybe_put("accept-ranges", upstream.accept_ranges)
      |> maybe_put("content-range", upstream.content_range)
      |> maybe_put("etag", upstream.etag)
      |> maybe_put("last-modified", upstream.last_modified)
      |> put_resp_content_type(upstream.content_type, nil)
      |> put_resp_header("cache-control", "public, max-age=300")
      |> send_resp(upstream.status, upstream.body)
    else
      {:error, {:not_allowed, host}} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(403, "pdf proxy: host not allowed: #{host}")

      {:error, reason} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(400, "pdf proxy: #{inspect(reason)}")
    end
  end

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(400, "pdf proxy: missing u")
  end

  # ── URL parsing / allow-list ──────────────────────────────────────

  defp parse_url(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host} = uri}
      when scheme in ["http", "https"] and is_binary(host) ->
        {:ok, uri}

      {:ok, _other} ->
        {:error, :unsupported_scheme}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_url(_url), do: {:error, :missing_url}

  defp ensure_allowed(%URI{host: host}) do
    if allowed_host?(host), do: :ok, else: {:error, {:not_allowed, host}}
  end

  defp allowed_host?(host) do
    host = String.downcase(host)

    Enum.any?(configured_hosts(), fn allowed ->
      host == allowed or String.ends_with?(host, "." <> allowed)
    end)
  end

  # OSS 的对象地址是 `<bucket>.<endpoint>`，所以 endpoint 自身和 bucket
  # 子域都要放行（后者是前者的子域，理论上一条就够，但 bucket 可被
  # `OSS_BUCKET` 覆盖成完全不同的域名，所以两条都给）。
  defp configured_hosts do
    endpoint = TcmEdu.Storage.OSS.endpoint()

    (Application.get_env(:tcm_edu, :pdf_proxy_hosts, []) ++
       ["#{TcmEdu.Storage.OSS.bucket()}.#{endpoint}", endpoint])
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  # ── Upstream fetch ────────────────────────────────────────────────

  defp fetch(uri, range, redirects_left) do
    headers = if range, do: [{"range", range}], else: []

    # `TcmEdu.AI.req_options()` 是本仓库给 Req 注入测试 plug 的统一开关
    # （`oss.ex` 等同），测试里换掉上游，不发真实请求。
    case Req.get(
           URI.to_string(uri),
           [
             headers: headers,
             redirect: false,
             retry: false,
             decode_body: false,
             receive_timeout: 30_000
           ] ++ TcmEdu.AI.req_options()
         ) do
      {:ok, %Req.Response{status: status} = resp} when status in [301, 302, 303, 307, 308] ->
        follow_redirect(resp, uri, range, redirects_left)

      {:ok, %Req.Response{status: status} = resp} when status in 200..299 ->
        to_upstream(resp, status)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:upstream_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # `header/2` 返回裸字符串或 nil，所以这里按值分支，不能用 `with` 去
  # 解构元组（那样任何一次真实重定向都会抛 WithClauseError → 500）。
  defp follow_redirect(resp, uri, range, redirects_left) when redirects_left > 0 do
    case header(resp, "location") do
      location when is_binary(location) ->
        with {:ok, next} <- URI.new(URI.merge(uri, location) |> URI.to_string()),
             :ok <- ensure_allowed(next) do
          fetch(next, range, redirects_left - 1)
        end

      _ ->
        {:error, :missing_location}
    end
  end

  defp follow_redirect(_resp, _uri, _range, _left), do: {:error, :too_many_redirects}

  defp to_upstream(resp, status) do
    if too_large?(resp) do
      {:error, :too_large}
    else
      {:ok,
       %{
         status: status,
         body: body(resp),
         content_type: header(resp, "content-type") || "application/pdf",
         content_range: header(resp, "content-range"),
         accept_ranges: header(resp, "accept-ranges"),
         etag: header(resp, "etag"),
         last_modified: header(resp, "last-modified")
       }}
    end
  end

  defp too_large?(resp) do
    case header(resp, "content-length") do
      nil -> byte_size(body(resp)) > @max_bytes
      len -> parse_int(len) > @max_bytes
    end
  end

  defp parse_int(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp body(%Req.Response{body: body}) when is_binary(body), do: body
  defp body(_resp), do: ""

  defp header(%Req.Response{} = resp, name) do
    case Req.Response.get_header(resp, name) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp range(conn) do
    case get_req_header(conn, "range") do
      [value | _] -> value
      _ -> nil
    end
  end

  defp maybe_put(conn, _name, nil), do: conn
  defp maybe_put(conn, name, value), do: put_resp_header(conn, name, value)
end
