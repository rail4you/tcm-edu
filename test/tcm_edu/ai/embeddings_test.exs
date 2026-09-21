defmodule TcmEdu.AI.EmbeddingsTest do
  @moduledoc """
  DashScope embedding 客户端测试（Req.Test stub，不发真实请求）。

  覆盖：
    * embed/2 成功解析向量
    * embed/2 API 错误 → {:error, {:api, status, msg}}
    * embed/2 未配置 key → {:error, :missing_key}
  """

  use ExUnit.Case, async: false

  alias TcmEdu.AI.Embeddings

  @base_url "https://dashscope.aliyuncs.com/compatible-mode/v1"

  setup do
    req_opts = [plug: {Req.Test, TcmEdu.AI.EmbeddingsTest}]

    Application.put_env(:tcm_edu, TcmEdu.AI,
      api_key_override: "sk-test-key",
      base_url: @base_url,
      embedding_model: "text-embedding-v3",
      embedding_dimensions: 1024,
      timeout: 5_000,
      req_options: req_opts
    )

    on_exit(fn ->
      Application.delete_env(:tcm_edu, TcmEdu.AI)
    end)

    :ok
  end

  test "embed/2 returns a vector per input" do
    Req.Test.stub(TcmEdu.AI.EmbeddingsTest, fn conn ->
      assert conn.method == "POST"
      assert String.ends_with?(conn.request_path, "/embeddings")
      assert get_in(conn.body_params, ["model"]) == "text-embedding-v3"
      assert get_in(conn.body_params, ["input"]) == ["中医基础理论", "桂枝汤"]

      Req.Test.json(conn, %{
        "data" => [
          %{"embedding" => List.duplicate(0.1, 1024), "index" => 0},
          %{"embedding" => List.duplicate(0.2, 1024), "index" => 1}
        ],
        "model" => "text-embedding-v3",
        "usage" => %{"prompt_tokens" => 6, "total_tokens" => 6}
      })
    end)

    assert {:ok, [v1, v2]} = Embeddings.embed(["中医基础理论", "桂枝汤"])
    assert length(v1) == 1024
    assert length(v2) == 1024
  end

  test "embed/2 returns missing_key error when no key configured" do
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)
    assert {:error, :missing_key} = Embeddings.embed(["hi"])
  end

  test "embed/2 surfaces API error" do
    Req.Test.stub(TcmEdu.AI.EmbeddingsTest, fn conn ->
      body = %{
        "error" => %{"message" => "Insufficient Balance", "code" => "invalid_request_error"}
      }

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(402, Jason.encode!(body))
      |> Plug.Conn.halt()
    end)

    assert {:error, {:api, 402, "Insufficient Balance"}} = Embeddings.embed(["hi"])
  end
end
