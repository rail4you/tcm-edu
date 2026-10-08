defmodule TcmEdu.AI.MedicalImageTest do
  @moduledoc """
  医学图片生成测试（Req.Test mock）：
    * 创建任务 → 轮询 SUCCEEDED → 返回 url 列表
    * 任务 FAILED → {:error, :task_failed}（带 message 时返回具体原因）
    * 尺寸 / 风格归一化后发给 DashScope（x→*，UI token→style token）
    * 创建任务 API 错误（如 402）
    * 未配置 key
  不触达真实 DashScope。
  """

  use ExUnit.Case, async: false

  alias TcmEdu.AI.MedicalImage

  @image_base "https://dashscope.aliyuncs.com/api/v1"

  setup do
    Application.put_env(:tcm_edu, TcmEdu.AI,
      api_key_override: "sk-test-key",
      image_model: "wanx2.1-t2i-turbo",
      image_base_url: @image_base,
      text_model: "qwen-flash",
      timeout: 5_000,
      req_options: [plug: {Req.Test, TcmEdu.AI.MedicalImageTest}]
    )

    on_exit(fn ->
      Application.delete_env(:tcm_edu, TcmEdu.AI)
    end)

    :ok
  end

  test "generate creates task then polls SUCCEEDED and returns urls" do
    Req.Test.stub(TcmEdu.AI.MedicalImageTest, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/api/v1/services/aigc/text2image/image-synthesis"} ->
          Req.Test.json(conn, %{
            "output" => %{"task_status" => "PENDING", "task_id" => "task-123"}
          })

        {"GET", "/api/v1/tasks/task-123"} ->
          Req.Test.json(conn, %{
            "output" => %{
              "task_status" => "SUCCEEDED",
              "results" => [%{"url" => "https://oss.example.com/heart.png"}]
            }
          })
      end
    end)

    assert {:ok, ["https://oss.example.com/heart.png"]} =
             MedicalImage.generate("解剖示意图：心脏，标注冠状血管，扁平插画，白底",
               interval_ms: 1
             )
  end

  test "generate returns :task_failed when task FAILED" do
    Req.Test.stub(TcmEdu.AI.MedicalImageTest, fn conn ->
      case conn.method do
        "POST" ->
          Req.Test.json(conn, %{"output" => %{"task_status" => "PENDING", "task_id" => "task-f"}})

        "GET" ->
          Req.Test.json(conn, %{"output" => %{"task_status" => "FAILED"}})
      end
    end)

    assert {:error, :task_failed} = MedicalImage.generate("x", interval_ms: 1)
  end

  test "generate surfaces DashScope failure message" do
    Req.Test.stub(TcmEdu.AI.MedicalImageTest, fn conn ->
      case conn.method do
        "POST" ->
          Req.Test.json(conn, %{
            "output" => %{"task_status" => "PENDING", "task_id" => "task-bad"}
          })

        "GET" ->
          Req.Test.json(conn, %{
            "output" => %{
              "task_status" => "FAILED",
              "code" => "InvalidParameter",
              "message" => "size is not in the correct format."
            }
          })
      end
    end)

    assert {:error, message} = MedicalImage.generate("x", interval_ms: 1)
    assert message =~ "size is not in the correct format."
  end

  test "normalizes size and style before calling DashScope" do
    Req.Test.stub(TcmEdu.AI.MedicalImageTest, fn conn ->
      assert conn.body_params["parameters"]["size"] == "1024*1024"
      assert conn.body_params["parameters"]["style"] == "<chinese painting>"
      Req.Test.json(conn, %{"output" => %{"task_status" => "PENDING", "task_id" => "task-1"}})
    end)

    assert {:ok, "task-1"} =
             MedicalImage.create_task("sk-test-key", "针灸图", size: "1024x1024", style: "ink")
  end

  test "maps 16:9 preset to a valid DashScope size" do
    Req.Test.stub(TcmEdu.AI.MedicalImageTest, fn conn ->
      assert conn.body_params["parameters"]["size"] == "1280*720"
      Req.Test.json(conn, %{"output" => %{"task_status" => "PENDING", "task_id" => "task-2"}})
    end)

    assert {:ok, "task-2"} = MedicalImage.create_task("sk-test-key", "x", size: "16:9")
  end

  test "generate surfaces create-task API error" do
    Req.Test.stub(TcmEdu.AI.MedicalImageTest, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(402, Jason.encode!(%{"message" => "Insufficient Balance"}))
      |> Plug.Conn.halt()
    end)

    assert {:error, {:api, 402, _}} = MedicalImage.generate("x", interval_ms: 1)
  end

  test "generate returns missing_key when no key configured" do
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    assert {:error, :missing_key} = MedicalImage.generate("x")
  end
end
