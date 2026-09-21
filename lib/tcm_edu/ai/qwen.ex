defmodule TcmEdu.AI.Qwen do
  @moduledoc """
  通义千问（DashScope OpenAI 兼容）客户端，用 `Req` 实现。

  **参考 KnowledgeHub 的 API 用法**：KnowledgeHub 用官方 OpenAI .NET SDK 直连
  `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`，
  system prompt + 历史 messages 流式对话，默认模型 `qwen-flash`。本模块用
  等价的 Req 实现，语义对齐：

    * `chat/2`        — 非流式，返回完整文本（对应 KnowledgeHub `GenerateReplyAsync`）
    * `chat_stream/3` — 流式，逐 delta 回调（对应 `GenerateReplyStreamingAsync`）

  模型与 key 由 `TcmEdu.AI` 解析（DB 存 key 优先，回退环境变量）。
  """

  require Logger

  alias TcmEdu.AI

  @type message :: AI.message()

  @doc """
  非流式对话。

  ## 参数

    * `messages` — 消息列表 `[%{role: "system"|"user"|"assistant", content: "..."}]`
    * `opts`     — `:model`（默认 qwen-flash）、`:max_tokens`、`:temperature`

  ## 返回

    * `{:ok, content}` — 模型回答文本
    * `{:error, reason}` — 失败原因（HTTP / 网络 / 未配置 key）
  """
  @spec chat([message()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def chat(messages, opts \\ []) do
    with {:ok, key} <- AI.api_key() do
      do_request(key, messages, opts)
    end
  end

  @doc """
  流式对话。

  `opts[:on_delta]` 回调在每段 delta 到达时被调用。返回拼好的完整文本。
  """
  @spec chat_stream([message()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def chat_stream(messages, opts \\ []) do
    with {:ok, key} <- AI.api_key() do
      do_request_stream(key, messages, opts)
    end
  end

  # ── 非流式 ───────────────────────────────────────────────

  defp do_request(key, messages, opts) do
    body = build_body(messages, opts, stream: false)

    case post(key, body) do
      {:ok, %{status: 200, body: response}} = resp ->
        case extract_message(response) do
          {:ok, content} -> {:ok, content}
          :empty -> {:error, :empty_response}
          _ -> {:error, {:unexpected, resp}}
        end

      {:ok, %{status: status, body: response_body}} ->
        log_error(status, response_body)
        {:error, api_error(status, response_body)}

      {:ok, %{status: status}} ->
        log_error(status, nil)
        {:error, {:http, status}}

      {:error, error} ->
        Logger.error("[Qwen] request error: #{inspect(error)}")
        {:error, {:transport, error}}
    end
  end

  # ── 流式 ─────────────────────────────────────────────────

  defp do_request_stream(key, messages, opts) do
    body = build_body(messages, opts, stream: true)
    on_delta = opts[:on_delta] || fn _ -> :ok end

    collect = fn
      {:data, chunk}, acc when is_binary(chunk) -> {:cont, [chunk | acc]}
      _event, acc -> {:cont, acc}
    end

    with {:ok, raw} <- post_stream(key, body, collect) do
      deltas = parse_sse_deltas(raw)
      Enum.each(deltas, &on_delta.(&1))
      {:ok, Enum.join(deltas, "")}
    end
  end

  @doc """
  把一整段原始 SSE 文本解析成文本 delta 列表。

  独立成纯函数，便于单测；`chat_stream/2` 内部也用它。

  ## 示例

      TcmEdu.AI.Qwen.parse_sse_deltas("data: {\\"choices\\":[{\\&quot;delta\\&quot;:{...}}]}\\n\\n")
  """
  @spec parse_sse_deltas(String.t()) :: [String.t()]
  def parse_sse_deltas(raw) do
    raw
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "data:"))
    |> Enum.map(&String.replace_prefix(&1, "data:", ""))
    |> Enum.map(&String.trim/1)
    |> Enum.map(&extract_delta/1)
    |> Enum.flat_map(fn
      {:ok, text} -> [text]
      :skip -> []
    end)
  end

  # ── Req 请求 ─────────────────────────────────────────────

  defp build_body(messages, opts, stream: stream) do
    %{
      model: opts[:model] || AI.text_model(),
      messages: normalize_messages(messages),
      max_tokens: opts[:max_tokens] || 4096,
      temperature: opts[:temperature] || 0.7,
      stream: stream
    }
  end

  defp normalize_messages(messages) when is_list(messages) do
    Enum.map(messages, fn
      %{role: role, content: content} -> %{role: to_string(role), content: to_string(content)}
      {role, content} -> %{role: to_string(role), content: to_string(content)}
    end)
  end

  defp normalize_messages(messages), do: normalize_messages([messages])

  defp url do
    AI.base_url()
    |> String.trim_trailing("/")
    |> Kernel.<>("/chat/completions")
  end

  defp headers(key) do
    %{"Authorization" => "Bearer #{key}", "Content-Type" => "application/json"}
  end

  defp post(key, body) do
    Req.post(url(), base_opts(key, body))
  end

  # 流式：用 Req 的 `into:` 回调攒原始 body 文本
  defp post_stream(key, body, collect) do
    Req.post(url(), base_opts(key, body) ++ [into: collect])
    |> case do
      {:ok, %{status: 200, body: acc}} when is_list(acc) ->
        {:ok, Enum.join(acc, "")}

      {:ok, %{status: 200, body: raw}} when is_binary(raw) ->
        {:ok, raw}

      {:ok, %{status: status, body: response_body}} ->
        log_err(status, response_body)
        {:error, {:http, status}}

      {:error, error} ->
        {:error, {:transport, error}}
    end
  rescue
    e -> {:error, {:transport, e}}
  end

  defp base_opts(key, body) do
    [
      json: body,
      headers: headers(key),
      receive_timeout: AI.timeout(),
      retry: false
    ] ++ AI.req_options()
  end

  defp log_err(status, body), do: log_error(status, body)

  # 从非流式响应取 content
  defp extract_message(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content) and content != "",
       do: {:ok, content}

  defp extract_message(%{"choices" => [%{"message" => %{"content" => ""}}]}), do: :empty
  defp extract_message(_), do: :error

  # 从一条 SSE `data: {...}` 行取 delta 文本
  defp extract_delta(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}}
      when is_binary(content) ->
        {:ok, content}

      _ ->
        :skip
    end
  end

  defp extract_delta(_), do: :skip

  defp api_error(status, body) do
    message = get_in(body, ["error", "message"]) || get_in(body, ["message"]) || "HTTP #{status}"
    {:api, status, message}
  end

  defp log_error(status, body) do
    Logger.error("[Qwen] API error #{status}: #{inspect(body)}")
  end
end
