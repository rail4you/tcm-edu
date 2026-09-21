defmodule TcmEdu.Storage.OSSServiceTest do
  @moduledoc """
  TcmEdu.Storage.OSS.Service（AshStorage.Service 实现）测试。
  验证 upload / url / delete / exists? 都委托给 TcmEdu.Storage.OSS。
  """

  use ExUnit.Case, async: false

  alias AshStorage.Service.Context
  alias TcmEdu.Storage.{OSS, OSS.Service}

  setup do
    Application.put_env(:tcm_edu, TcmEdu.AI,
      req_options: [plug: {Req.Test, TcmEdu.Storage.OSSServiceTest}]
    )

    on_exit(fn ->
      Application.delete_env(:tcm_edu, TcmEdu.AI)
    end)

    :ok
  end

  test "upload delegates to OSS.upload_bytes and returns :ok" do
    bucket = OSS.bucket()

    Req.Test.stub(TcmEdu.Storage.OSSServiceTest, fn conn ->
      assert conn.method == "PUT"
      assert conn.host == "#{bucket}.#{OSS.endpoint()}"

      conn
      |> Plug.Conn.send_resp(200, "")
      |> Plug.Conn.halt()
    end)

    ctx = Context.new([], content_type: "image/png", filename: "x.png")
    assert :ok = Service.upload("avatars/x.png", <<1, 2, 3>>, ctx)
  end

  test "url returns a signed OSS URL (bucket is private)" do
    ctx = Context.new([])
    url = Service.url("avatars/x.png", ctx)

    assert url =~ OSS.public_url(bucket(), "avatars/x.png")
    assert url =~ "OSSAccessKeyId=#{OSS.access_key_id()}"
    assert url =~ "Expires="
    assert url =~ "Signature="
  end

  test "delete issues DELETE and returns :ok on 204" do
    bucket = OSS.bucket()

    Req.Test.stub(TcmEdu.Storage.OSSServiceTest, fn conn ->
      assert conn.method == "DELETE"
      assert conn.host == "#{bucket}.#{OSS.endpoint()}"
      conn |> Plug.Conn.send_resp(204, "") |> Plug.Conn.halt()
    end)

    ctx = Context.new([])
    assert :ok = Service.delete("avatars/x.png", ctx)
  end

  test "exists? returns true on 200 and false on 404" do
    counter = :counters.new(1, [])

    Req.Test.stub(TcmEdu.Storage.OSSServiceTest, fn conn ->
      :counters.add(counter, 1, 1)

      case :counters.get(counter, 1) do
        1 ->
          conn |> Plug.Conn.send_resp(200, "") |> Plug.Conn.halt()

        _ ->
          conn |> Plug.Conn.send_resp(404, "") |> Plug.Conn.halt()
      end
    end)

    ctx = Context.new([])

    assert {:ok, true} = Service.exists?("avatars/x.png", ctx)
    assert {:ok, false} = Service.exists?("avatars/missing.png", ctx)
  end

  test "download returns :not_found on 404" do
    Req.Test.stub(TcmEdu.Storage.OSSServiceTest, fn conn ->
      conn |> Plug.Conn.send_resp(404, "") |> Plug.Conn.halt()
    end)

    ctx = Context.new([])
    assert {:error, :not_found} = Service.download("avatars/missing.png", ctx)
  end

  defp bucket, do: OSS.bucket()
end
