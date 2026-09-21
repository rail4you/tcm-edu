defmodule TcmEdu.AI.MedicalImageStoreTest do
  @moduledoc """
  MedicalImage.generate_and_store 测试：模拟 DashScope 生成 + OSS 上传链路。
  """

  use ExUnit.Case, async: false

  alias TcmEdu.AI.MedicalImage
  alias TcmEdu.Storage.OSS

  setup do
    Application.put_env(:tcm_edu, TcmEdu.AI,
      api_key_override: "sk-test-key",
      image_model: "wanx2.1-t2i-turbo",
      image_base_url: "https://dashscope.aliyuncs.com/api/v1",
      text_model: "qwen-flash",
      timeout: 5_000,
      req_options: [plug: {Req.Test, TcmEdu.AI.MedicalImageStoreTest}]
    )

    on_exit(fn ->
      Application.delete_env(:tcm_edu, TcmEdu.AI)
    end)

    :ok
  end

  test "generate_and_store returns OSS URL after upload" do
    bucket = OSS.bucket()
    oss_host = "#{bucket}.#{OSS.endpoint()}"

    Req.Test.stub(TcmEdu.AI.MedicalImageStoreTest, fn conn ->
      case {conn.method, conn.host, conn.request_path} do
        {"POST", "dashscope.aliyuncs.com", "/api/v1/services/aigc/text2image/image-synthesis"} ->
          Req.Test.json(conn, %{"output" => %{"task_status" => "PENDING", "task_id" => "t-1"}})

        {"GET", "dashscope.aliyuncs.com", "/api/v1/tasks/t-1"} ->
          Req.Test.json(conn, %{
            "output" => %{
              "task_status" => "SUCCEEDED",
              "results" => [
                %{"url" => "https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/x/heart.png"}
              ]
            }
          })

        # OSS download (GET) → 返回 PNG bytes
        {"GET", "dashscope-result-bj.oss-cn-beijing.aliyuncs.com", "/x/heart.png"} ->
          conn
          |> Plug.Conn.put_resp_content_type("image/png")
          |> Plug.Conn.send_resp(200, <<137, 80, 78, 71>>)
          |> Plug.Conn.halt()

        # OSS upload (PUT) → 200
        {"PUT", ^oss_host, _path} ->
          conn
          |> Plug.Conn.send_resp(200, "")
          |> Plug.Conn.halt()
      end
    end)

    assert {:ok, [oss_url]} =
             MedicalImage.generate_and_store("解剖示意图：心脏", interval_ms: 1, key_prefix: "ai")

    assert oss_url =~ ~r|^https://#{oss_host}/ai/|
    assert oss_url =~ "OSSAccessKeyId="
    assert oss_url =~ "Signature="
  end

  test "generate_and_store surfaces upload failure" do
    Req.Test.stub(TcmEdu.AI.MedicalImageStoreTest, fn conn ->
      case {conn.method, conn.host, conn.request_path} do
        {"POST", "dashscope.aliyuncs.com", "/api/v1/services/aigc/text2image/image-synthesis"} ->
          Req.Test.json(conn, %{"output" => %{"task_status" => "PENDING", "task_id" => "t-f"}})

        {"GET", "dashscope.aliyuncs.com", "/api/v1/tasks/t-f"} ->
          Req.Test.json(conn, %{
            "output" => %{
              "task_status" => "SUCCEEDED",
              "results" => [
                %{"url" => "https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/x/p.png"}
              ]
            }
          })

        {"GET", "dashscope-result-bj.oss-cn-beijing.aliyuncs.com", "/x/p.png"} ->
          conn
          |> Plug.Conn.put_resp_content_type("image/png")
          |> Plug.Conn.send_resp(200, <<1, 2, 3>>)
          |> Plug.Conn.halt()

        {"PUT", _host, _path} ->
          conn
          |> Plug.Conn.send_resp(403, "AccessDenied")
          |> Plug.Conn.halt()
      end
    end)

    assert {:error, {:upload_failed, 403, _}} =
             MedicalImage.generate_and_store("x", interval_ms: 1)
  end
end
