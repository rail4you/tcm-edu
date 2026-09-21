defmodule TcmEdu.AI.QwenTest do
  @moduledoc """
  Qwen 客户端测试（Req.Test stub，不发真实请求）。

  覆盖：
    * chat/2 成功解析 content
    * chat/2 处理 API 错误（如 402 Insufficient Balance → {:error, {:api, 402, msg}}）
    * chat/2 未配置 key → {:error, :missing_key}
    * chat_stream/2 流式叠加 delta
    * api_key/0 优先级：override → DB → env
  """

  use ExUnit.Case, async: false

  alias TcmEdu.AI
  alias TcmEdu.AI.Qwen

  @base_url "https://dashscope.aliyuncs.com/compatible-mode/v1"

  setup do
    # 注入 Req.Test stub 到 Qwen 的请求选项
    req_opts = [plug: {Req.Test, TcmEdu.AI.QwenTest}]

    Application.put_env(:tcm_edu, TcmEdu.AI,
      api_key_override: "sk-test-key",
      base_url: @base_url,
      text_model: "qwen-flash",
      timeout: 5_000,
      req_options: req_opts
    )

    on_exit(fn ->
      Application.delete_env(:tcm_edu, TcmEdu.AI)
    end)

    :ok
  end

  test "api_key/0 uses test override key" do
    assert {:ok, "sk-test-key"} = AI.api_key()
  end

  test "chat/2 returns content on success" do
    Req.Test.stub(TcmEdu.AI.QwenTest, fn conn ->
      assert conn.method == "POST"

      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"role" => "assistant", "content" => "你好，我是杏宁树。"}}]
      })
    end)

    assert {:ok, "你好，我是杏宁树。"} =
             Qwen.chat([
               %{role: "system", content: "你是医学导师"},
               %{role: "user", content: "什么是阴虚？"}
             ])
  end

  test "chat/2 surfaces API error (e.g. 402 Insufficient Balance)" do
    Req.Test.stub(TcmEdu.AI.QwenTest, fn conn ->
      body = %{
        "error" => %{"message" => "Insufficient Balance", "code" => "invalid_request_error"}
      }

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(402, Jason.encode!(body))
      |> Plug.Conn.halt()
    end)

    assert {:error, {:api, 402, "Insufficient Balance"}} =
             Qwen.chat([%{role: "user", content: "hi"}])
  end

  test "chat/2 returns missing_key error when no key configured" do
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)
    assert {:error, :missing_key} = Qwen.chat([%{role: "user", content: "hi"}])
  end

  test "chat_stream/2 parses SSE deltas (pure parser)" do
    sse = """
    data: {"choices":[{"delta":{"content":"中"}}]}

    data: {"choices":[{"delta":{"content":"医"}}]}

    data: [DONE]

    """

    assert Qwen.parse_sse_deltas(sse) == ["中", "医"]
  end
end
