defmodule TcmEdu.AI.MedicalImage do
  @moduledoc """
  医学图片生成（合同 §1.6.2 · AI 生成式内容引擎；计划 F5）。

  基于 DashScope 万相文生图 `wanx2.1-t2i-turbo`。图像处理较慢，DashScope
  HTTP 仅支持**异步任务**：

    1. `POST /api/v1/services/aigc/text2image/image-synthesis`
       （`X-DashScope-Async: enable`）→ 返回 `task_id`
    2. `GET  /api/v1/tasks/{task_id}` 轮询 → `task_status` + `results[].url`

  ## 医学场景

    * 解剖示意图（心脏 / 肺 / 肝 / 骨骼）
    * 病理组织图
    * 器械示意图
    * 教学配图（封面 / 章节头图）

  默认风格 `<flat illustration>`（扁平插画）+ 白底贴标签，较适合医学示意图。
  """

  require Logger

  alias TcmEdu.AI

  @doc """
  生成图片（创建任务 + 轮询到完成）。

  ## 参数

    * `prompt` — 正向提示词（中文，≤800 字符）
    * `opts`   — `:style`（如 `<flat illustration>`）、`:size`（如 `1024*1024`）、
                `:n`（张数）、`:max_polls`、`:interval_ms`

  ## 返回

    * `{:ok, [url]}` — 生成的图片 URL 列表（有效期 24h，**需尽快转存 OSS**）
    * `{:error, reason}` — 未配置 key / 失败任务 / 轮询超时
  """
  @spec generate(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def generate(prompt, opts \\ []) do
    with {:ok, key} <- AI.api_key(),
         {:ok, task_id} <- create_task(key, prompt, opts) do
      poll_task(key, task_id, opts)
    end
  end

  @doc """
  一步生成并落库到 `xingningshu` OSS bucket（避免 24h URL 过期）。

  ## 参数

    * `prompt` — 同 `generate/2`
    * `opts`   — `:key_prefix`（默认 `"ai"`）、`:style`、`:size`、`:n`、
                `:max_polls`、`:interval_ms`

  ## 返回

    * `{:ok, [oss_url]}` — 落在 OSS 上的公开 URL 列表
    * `{:error, reason}` — 任一步骤失败
  """
  @spec generate_and_store(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def generate_and_store(prompt, opts \\ []) do
    prefix = opts[:key_prefix] || "ai"

    with {:ok, urls} <- generate(prompt, opts) do
      urls
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {url, idx}, {:ok, acc} ->
        ext = Path.extname(URI.parse(url).path || "") |> String.downcase()
        ext = if ext == "", do: ".png", else: ext
        key = "#{prefix}/#{prompt_hash(prompt)}-#{idx}#{ext}"

        case TcmEdu.Storage.OSS.upload_from_url(url, key) do
          {:ok, _oss_url} ->
            # bucket 私有 → 返回预签名 URL，前端可直接 <img>
            case TcmEdu.Storage.OSS.signed_url(key) do
              {:ok, signed} -> {:cont, {:ok, [signed | acc]}}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, list} -> {:ok, Enum.reverse(list)}
        err -> err
      end
    end
  end

  defp prompt_hash(prompt) do
    :crypto.hash(:sha256, prompt) |> Base.encode16(case: :lower) |> binary_part(0, 12)
  end

  @doc """
  创建文生图异步任务。返回 `{:ok, task_id}` 或 `{:error, reason}`。
  """
  @spec create_task(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def create_task(key, prompt, opts \\ []) do
    body = %{
      model: opts[:model] || AI.image_model(),
      input: %{
        prompt: prompt,
        negative_prompt: opts[:negative_prompt] || "低质量、模糊、变形、多余手指、文字水印、错乱解剖结构"
      },
      parameters: %{
        style: opts[:style] || "<flat illustration>",
        size: opts[:size] || "1024*1024",
        n: opts[:n] || 1
      }
    }

    headers = %{
      "Authorization" => "Bearer #{key}",
      "Content-Type" => "application/json",
      "X-DashScope-Async" => "enable"
    }

    case Req.post(
           AI.image_base_url() <> "/services/aigc/text2image/image-synthesis",
           [
             json: body,
             headers: headers,
             receive_timeout: 30_000,
             retry: false
           ] ++ AI.req_options()
         ) do
      {:ok, %{status: 200, body: %{"output" => %{"task_id" => task_id}}}}
      when is_binary(task_id) ->
        {:ok, task_id}

      {:ok, %{status: status, body: response_body}} ->
        log_error(status, response_body)
        {:error, api_error(status, response_body)}

      {:error, error} ->
        Logger.error("[MedicalImage] create_task transport: #{inspect(error)}")
        {:error, {:transport, error}}
    end
  end

  @doc """
  查询单个任务状态。返回 `{:ok, %{status: ..., urls: [...]}}` 或 `{:error, reason}`。
  """
  @spec get_task(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_task(key, task_id) do
    url = AI.image_base_url() <> "/tasks/" <> task_id

    case Req.get(
           url,
           [headers: %{"Authorization" => "Bearer #{key}"}, retry: false] ++ AI.req_options()
         ) do
      {:ok, %{status: 200, body: %{"output" => output}}} ->
        {:ok, parse_output(output)}

      {:ok, %{status: status, body: response_body}} ->
        log_error(status, response_body)
        {:error, api_error(status, response_body)}

      {:error, error} ->
        Logger.error("[MedicalImage] get_task transport: #{inspect(error)}")
        {:error, {:transport, error}}
    end
  end

  # ── 轮询 ───────────────────────────────────────────────

  defp poll_task(key, task_id, opts) do
    max_polls = opts[:max_polls] || 30
    interval = opts[:interval_ms] || 2_000
    do_poll(key, task_id, max_polls, interval)
  end

  defp do_poll(_key, _task_id, 0, _interval) do
    Logger.warning("[MedicalImage] poll timeout")
    {:error, :poll_timeout}
  end

  defp do_poll(key, task_id, attempts, interval) do
    case get_task(key, task_id) do
      {:ok, %{status: "SUCCEEDED", urls: urls}} when urls != [] ->
        {:ok, urls}

      {:ok, %{status: "SUCCEEDED"}} ->
        {:ok, []}

      {:ok, %{status: "FAILED", urls: _urls}} ->
        {:error, :task_failed}

      {:ok, %{status: status}} when status in ["PENDING", "RUNNING"] ->
        Process.sleep(interval)
        do_poll(key, task_id, attempts - 1, interval)

      {:ok, %{status: other}} ->
        {:error, {:unexpected_status, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_output(%{"task_status" => status, "results" => results}) do
    urls =
      Enum.flat_map(results || [], fn
        %{"url" => url} -> [url]
        _ -> []
      end)

    %{status: status, urls: urls}
  end

  defp parse_output(%{"task_status" => status}) do
    %{status: status, urls: []}
  end

  defp parse_output(_), do: %{status: "UNKNOWN", urls: []}

  defp api_error(status, body) do
    message = get_in(body, ["message"]) || get_in(body, ["code"]) || "HTTP #{status}"
    {:api, status, message}
  end

  defp log_error(status, body) do
    Logger.error("[MedicalImage] API error #{status}: #{inspect(body)}")
  end
end
