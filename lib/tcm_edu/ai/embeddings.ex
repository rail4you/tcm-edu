defmodule TcmEdu.AI.Embeddings do
  @moduledoc """
  DashScope 文本向量客户端（OpenAI 兼容 `/embeddings`）。

  Qwen embedding 端点（实测可用）：
    `POST https://dashscope.aliyuncs.com/compatible-mode/v1/embeddings`
    model: `text-embedding-v3`（默认 1024 维，可 `dimensions` 降为 768/512）或 `text-embedding-v4`

  凭证复用 `TcmEdu.AI.api_key/0`（DB `ApiKeyConfig` → 环境变量，测试可注入
  `api_key_override`），请求选项可通过 `AI.req_options/0` 注入（测试 mock）。
  """

  require Logger

  alias TcmEdu.AI

  @type vector :: [float()]

  @default_model "text-embedding-v3"
  @default_dimensions 1024

  @doc "默认 embedding 模型"
  def model, do: Application.get_env(:tcm_edu, TcmEdu.AI, [])[:embedding_model] || @default_model

  @doc "默认向量维度"
  def dimensions,
    do: Application.get_env(:tcm_edu, TcmEdu.AI, [])[:embedding_dimensions] || @default_dimensions

  @doc """
  为一组文本生成向量。

  ## 参数

    * `texts` — 文本列表（DashScope 单次 ≤ 25 条，每条 ≤ 8192 token）
    * `opts`  — `:model`、`:dimensions`

  ## 返回

    * `{:ok, [vector]}` — 与 `texts` 一一对应的向量列表
    * `{:error, reason}` — 未配置 key / HTTP 错误 / 网络错误
  """
  @spec embed([String.t()], keyword()) :: {:ok, [vector()]} | {:error, term()}
  def embed(texts, opts \\ []) do
    with {:ok, key} <- AI.api_key() do
      request(key, texts, opts)
    end
  end

  defp request(key, texts, opts) do
    body = %{
      model: opts[:model] || model(),
      input: texts,
      dimensions: opts[:dimensions] || dimensions()
    }

    headers = %{
      "Authorization" => "Bearer #{key}",
      "Content-Type" => "application/json"
    }

    case Req.post(
           embedding_url(),
           [
             json: body,
             headers: headers,
             receive_timeout: AI.timeout(),
             retry: false
           ] ++ AI.req_options()
         ) do
      {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
        vectors =
          Enum.map(data, fn
            %{"embedding" => embedding} when is_list(embedding) -> embedding
            _ -> []
          end)

        {:ok, vectors}

      {:ok, %{status: status, body: response_body}} ->
        log_error(status, response_body)
        {:error, api_error(status, response_body)}

      {:error, error} ->
        Logger.error("[Embeddings] transport: #{inspect(error)}")
        {:error, {:transport, error}}
    end
  end

  defp embedding_url do
    AI.base_url()
    |> String.trim_trailing("/")
    |> Kernel.<>("/embeddings")
  end

  defp api_error(status, body) do
    message = get_in(body, ["error", "message"]) || get_in(body, ["message"]) || "HTTP #{status}"
    {:api, status, message}
  end

  defp log_error(status, body) do
    Logger.error("[Embeddings] API error #{status}: #{inspect(body)}")
  end
end
