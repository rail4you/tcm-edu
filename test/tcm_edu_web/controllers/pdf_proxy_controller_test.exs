defmodule TcmEduWeb.PdfProxyControllerTest do
  @moduledoc """
  `/pdfjs/doc?u=…` 同源 PDF 转发端点测试。

  覆盖三件事：
    * URL 校验（缺参 / 非 http(s) scheme）
    * SSRF 白名单（含「query 里塞白名单域名」的绕过尝试、重定向出圈）
    * Range 透传与响应头中继

  上游用 `Req.Test` mock，不发真实请求。
  """

  use TcmEduWeb.ConnCase, async: false

  alias TcmEdu.Storage.OSS

  @stub TcmEduWeb.PdfProxyControllerTest

  setup do
    Application.put_env(:tcm_edu, TcmEdu.AI, req_options: [plug: {Req.Test, @stub}])
    on_exit(fn -> Application.delete_env(:tcm_edu, TcmEdu.AI) end)

    :ok
  end

  describe "URL 校验" do
    test "缺少 u 返回 400", %{conn: conn} do
      conn = get(conn, "/pdfjs/doc")

      assert conn.status == 400
      assert conn.resp_body =~ "missing u"
    end

    test "非 http(s) scheme 返回 400", %{conn: conn} do
      conn = get(conn, "/pdfjs/doc", %{"u" => "file:///etc/passwd"})

      assert conn.status == 400
      assert conn.resp_body =~ "unsupported_scheme"
    end

    test "白名单主机名单独出现在 query 里不算放行", %{conn: conn} do
      conn = get(conn, "/pdfjs/doc", %{"u" => "http://evil.example/?h=www.w3.org"})

      assert conn.status == 403
      assert conn.resp_body =~ "host not allowed: evil.example"
    end

    test "白名单主机的子域放行", %{conn: conn} do
      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/pdf")
        |> Plug.Conn.send_resp(200, "%PDF-1.4 x")
        |> Plug.Conn.halt()
      end)

      conn = get(conn, "/pdfjs/doc", %{"u" => "https://cdn.mozilla.github.io/a.pdf"})

      assert conn.status == 200
      assert conn.resp_body == "%PDF-1.4 x"
    end
  end

  describe "SSRF 白名单" do
    test "内网地址被拒绝", %{conn: conn} do
      conn = get(conn, "/pdfjs/doc", %{"u" => "http://169.254.169.254/latest/meta-data/"})

      assert conn.status == 403
      assert conn.resp_body =~ "169.254.169.254"
    end

    test "OSS bucket 域名自动放行", %{conn: conn} do
      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.send_resp(500, "boom")
        |> Plug.Conn.halt()
      end)

      url = "https://#{OSS.bucket()}.#{OSS.endpoint()}/notes/a.pdf"
      conn = get(conn, "/pdfjs/doc", %{"u" => url})

      # 进到了上游（500 → 400），说明没被 403 拦在白名单外
      assert conn.status == 400
      assert conn.resp_body =~ "upstream_status"
    end

    test "重定向到白名单外的主机被拒绝", %{conn: conn} do
      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "http://127.0.0.1/steal")
        |> Plug.Conn.send_resp(302, "")
        |> Plug.Conn.halt()
      end)

      conn = get(conn, "/pdfjs/doc", %{"u" => "https://www.w3.org/redirect.pdf"})

      assert conn.status == 403
      assert conn.resp_body =~ "127.0.0.1"
    end
  end

  describe "转发行为" do
    test "中继 content-type 与 cache-control", %{conn: conn} do
      Req.Test.stub(@stub, fn conn ->
        assert conn.host == "www.w3.org"

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/pdf")
        |> Plug.Conn.send_resp(200, "%PDF-1.4 dummy")
        |> Plug.Conn.halt()
      end)

      conn = get(conn, "/pdfjs/doc", %{"u" => "https://www.w3.org/dummy.pdf"})

      assert conn.status == 200
      assert conn.resp_body == "%PDF-1.4 dummy"
      assert get_resp_header(conn, "content-type") == ["application/pdf"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=300"]
    end

    test "透传 Range 并中继 content-range / accept-ranges", %{conn: conn} do
      Req.Test.stub(@stub, fn conn ->
        assert Plug.Conn.get_req_header(conn, "range") == ["bytes=0-1023"]

        conn
        |> Plug.Conn.put_resp_header("content-range", "bytes 0-1023/13264")
        |> Plug.Conn.put_resp_header("accept-ranges", "bytes")
        |> Plug.Conn.send_resp(206, "%PDF")
        |> Plug.Conn.halt()
      end)

      conn =
        conn
        |> put_req_header("range", "bytes=0-1023")
        |> get("/pdfjs/doc", %{"u" => "https://www.w3.org/dummy.pdf"})

      assert conn.status == 206
      assert conn.resp_body == "%PDF"
      assert get_resp_header(conn, "content-range") == ["bytes 0-1023/13264"]
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    end

    test "跟随指向白名单内主机的重定向", %{conn: conn} do
      Req.Test.stub(@stub, fn conn ->
        case {conn.host, conn.request_path} do
          {"www.w3.org", "/jump.pdf"} ->
            conn
            |> Plug.Conn.put_resp_header("location", "https://cdn.mozilla.github.io/real.pdf")
            |> Plug.Conn.send_resp(302, "")
            |> Plug.Conn.halt()

          {"cdn.mozilla.github.io", "/real.pdf"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/pdf")
            |> Plug.Conn.send_resp(200, "%PDF-1.4 redirected")
            |> Plug.Conn.halt()
        end
      end)

      conn = get(conn, "/pdfjs/doc", %{"u" => "https://www.w3.org/jump.pdf"})

      assert conn.status == 200
      assert conn.resp_body == "%PDF-1.4 redirected"
    end

    test "上游非 2xx 返回 400", %{conn: conn} do
      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.send_resp(404, "nope")
        |> Plug.Conn.halt()
      end)

      conn = get(conn, "/pdfjs/doc", %{"u" => "https://www.w3.org/gone.pdf"})

      assert conn.status == 400
      assert conn.resp_body =~ "upstream_status"
    end
  end

  describe "静态资源" do
    # `Plug.Static` 默认只放行 `static_paths/0`，`pdfjs` 必须在名单里；
    # viewer.html 还必须指向 legacy 构建（设备 WebView 是 Chrome 113，
    # 跑不动 pdf.js 6.x 的 ES2025 `Iterator`）。
    test "自托管 pdf.js viewer 可访问且指向 legacy 构建", %{conn: conn} do
      conn = get(conn, "/pdfjs/web/viewer.html")

      assert conn.status == 200
      assert conn.resp_body =~ "src=\"../legacy/build/pdf.mjs\""
      refute conn.resp_body =~ "src=\"../build/pdf.mjs\""
    end

    test "legacy 构建与 worker 可访问，且模块脚本带 JS MIME", %{conn: conn} do
      for path <- [
            "/pdfjs/legacy/build/pdf.mjs",
            "/pdfjs/legacy/build/pdf.worker.mjs",
            "/pdfjs/web/viewer.mjs"
          ] do
        conn = get(conn, path)
        assert conn.status == 200, "expected 200 for #{path}, got #{conn.status}"
        assert byte_size(conn.resp_body) > 0
        assert [type] = get_resp_header(conn, "content-type")
        assert type =~ ~r{^text/javascript}
      end

      assert get(conn, "/pdfjs/LICENSE").status == 200
    end
  end
end
