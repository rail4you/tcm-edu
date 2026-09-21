defmodule TcmEdu.Storage.OSSTest do
  @moduledoc """
  OSS 客户端测试（Req.Test mock，不发真实 OSS 请求）。

  覆盖：
    * upload_bytes 签名与 URL 正确（含 Authorization 头可验签）
    * upload_from_url 下载 + 上传
    * sign_put_headers 单独可调用且符合 v1 规范
    * public_url 拼接
    * 公开 URL 过期/默认 bucket 配置
  """

  use ExUnit.Case, async: false

  alias TcmEdu.Storage.OSS

  setup do
    # 把测试 plug 注入到 AI 的 req_options（OSS 与 Qwen 共享同一开关）
    req_opts = [plug: {Req.Test, TcmEdu.Storage.OSSTest}]
    Application.put_env(:tcm_edu, TcmEdu.AI, req_options: req_opts)

    on_exit(fn ->
      Application.delete_env(:tcm_edu, TcmEdu.AI)
    end)

    :ok
  end

  test "public_url builds the OSS path" do
    assert OSS.public_url("xingningshu", "ai/heart.png") ==
             "https://xingningshu.oss-cn-beijing.aliyuncs.com/ai/heart.png"
  end

  test "sign_put_headers produces v1 HMAC-SHA1 signature" do
    headers = OSS.sign_put_headers("ai/heart.png", content_type: "image/png")

    assert headers["Content-Type"] == "image/png"
    assert headers["Date"] =~ ~r/^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} GMT$/
    assert headers["Authorization"] =~ ~r/^OSS #{OSS.access_key_id()}:[A-Za-z0-9+\/=]+$/

    # 验签：手工重算期望 signature，比较
    expected_sig =
      :crypto.mac(
        :hmac,
        :sha,
        OSS.access_key_secret(),
        "PUT\n\nimage/png\n#{headers["Date"]}\n/xingningshu/ai/heart.png"
      )
      |> Base.encode64()

    assert [_, actual_sig] =
             Regex.run(~r/^OSS #{OSS.access_key_id()}:(.+)$/, headers["Authorization"])

    assert actual_sig == expected_sig
  end

  test "signed_url builds a v1 presigned GET URL" do
    {:ok, url} = OSS.signed_url("ai/heart.png")

    assert url =~ "OSSAccessKeyId=#{OSS.access_key_id()}"
    assert url =~ "Expires="
    assert url =~ "Signature="
  end

  test "upload_bytes PUTs to OSS with signed headers and returns public URL" do
    bucket = OSS.bucket()

    Req.Test.stub(TcmEdu.Storage.OSSTest, fn conn ->
      # 断言：PUT、目标 key、Authorization 头
      assert conn.method == "PUT"
      assert conn.request_path == "/ai/heart.png"
      assert conn.host == "#{bucket}.#{OSS.endpoint()}"

      assert [auth] = Plug.Conn.get_req_header(conn, "authorization")

      assert auth =~ ~r/^OSS #{OSS.access_key_id()}:/
      assert "image/png" in Plug.Conn.get_req_header(conn, "content-type")

      conn
      |> Plug.Conn.send_resp(200, "")
      |> Plug.Conn.halt()
    end)

    assert {:ok, url} =
             OSS.upload_bytes(<<137, 80, 78, 71>>, "ai/heart.png", content_type: "image/png")

    assert url == "https://#{bucket}.#{OSS.endpoint()}/ai/heart.png"
  end

  test "upload_bytes surfaces upload error (4xx)" do
    Req.Test.stub(TcmEdu.Storage.OSSTest, fn conn ->
      conn
      |> Plug.Conn.send_resp(403, Jason.encode!(%{"Code" => "AccessDenied"}))
      |> Plug.Conn.halt()
    end)

    assert {:error, {:upload_failed, 403, _body}} =
             OSS.upload_bytes(<<1, 2, 3>>, "x.png", content_type: "image/png")
  end

  test "upload_from_url downloads then uploads, returning OSS URL" do
    bucket = OSS.bucket()
    oss_host = "#{bucket}.#{OSS.endpoint()}"
    remote_url = "https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/123/heart.png"

    Req.Test.stub(TcmEdu.Storage.OSSTest, fn conn ->
      case {conn.method, conn.host, conn.request_path} do
        {"GET", "dashscope-result-bj.oss-cn-beijing.aliyuncs.com", "/123/heart.png"} ->
          conn
          |> Plug.Conn.put_resp_content_type("image/png")
          |> Plug.Conn.send_resp(200, <<137, 80, 78, 71>>)
          |> Plug.Conn.halt()

        {"PUT", ^oss_host, "/ai/from-url.png"} ->
          conn
          |> Plug.Conn.send_resp(200, "")
          |> Plug.Conn.halt()
      end
    end)

    assert {:ok, url} = OSS.upload_from_url(remote_url, "ai/from-url.png")

    assert url == "https://#{oss_host}/ai/from-url.png"
  end

  test "upload_from_url surfaces download failure" do
    Req.Test.stub(TcmEdu.Storage.OSSTest, fn conn ->
      # 只有 GET 走这个分支（下载阶段）；PUT 不会到这里
      if conn.method == "GET" do
        conn
        |> Plug.Conn.send_resp(500, "boom")
        |> Plug.Conn.halt()
      else
        # 不应有 PUT；如果到了返回错误以便排查
        conn
        |> Plug.Conn.send_resp(500, "unexpected PUT")
        |> Plug.Conn.halt()
      end
    end)

    assert {:error, {:download_failed, _}} =
             OSS.upload_from_url("https://example.com/x.png", "ai/x.png")
  end
end
