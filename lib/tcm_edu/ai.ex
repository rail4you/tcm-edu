defmodule TcmEdu.AI do
  @moduledoc """
  杏宁树 AI 服务门面。

  定义共享的 provider / 模型配置来源，并负责解析 API key：

    1. 优先从数据库 `TcmEdu.System.ApiKeyConfig`（provider）读（沿用 kg-edu 方案，
       super admin 可运行时改，无需重启）
    2. 回退到环境变量 `QWEN_API_KEY` / `DASHSCOPE_API_KEY`
    3. 再把 key 注入 `:req_llm`（`alibaba_cn`）供 Jido/ReqLLM agent 复用

  模型与接口约定参考 **KnowledgeHub**（DashScope OpenAI 兼容 `/chat/completions`）：
    * 文本   `qwen-flash`
    * 视觉   `qwen3-vl-flash`
    * 更强    `qwen-plus`
  """

  @typedoc "统一返回 {role, content} 的消息结构（knowledgehub 样式）"
  @type message :: %{required(:role) => String.t(), required(:content) => String.t()}

  require Ash.Query

  # 编译期固化环境（release 运行时无 Mix 模块，不能在函数内调用 Mix.env/0）
  @env Mix.env()

  @base_url "https://dashscope.aliyuncs.com/compatible-mode/v1"
  @providers [:qwen, :dashscope]

  @doc "返回配置的环境变量名"
  def env_keys, do: ~w(QWEN_API_KEY DASHSCOPE_API_KEY)

  @doc """
  解析 Qwen API key。

  优先级：
    1. 测试注入 `Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: ...)`
    2. 数据库 `ApiKeyConfig`
    3. 环境变量 `QWEN_API_KEY` / `DASHSCOPE_API_KEY`

  ## 返回

    * `{:ok, key}` — 取到非空 key
    * `{:error, :missing_key}` — 未配置
  """
  @spec api_key() :: {:ok, String.t()} | {:error, :missing_key}
  def api_key do
    with {:ok, key} <- from_override_or_config() do
      ensure_req_llm_key(key)
      {:ok, key}
    end
  end

  @doc "直接读取 key（不注入 ReqLLM）"
  @spec api_key_raw() :: {:ok, String.t()} | {:error, :missing_key}
  def api_key_raw, do: from_override_or_config()

  # override 优先级：
  #   - 二进制 key → 用之
  #   - :none → 强制无 key（测试断言 missing_key 用，避免受系统 env 影响）
  #   - 未设定（nil）→ DB → env
  defp from_override_or_config do
    case Application.get_env(:tcm_edu, TcmEdu.AI, [])[:api_key_override] do
      key when is_binary(key) and key != "" ->
        {:ok, key}

      :none ->
        {:error, :missing_key}

      nil ->
        from_db_or_env()
    end
  end

  # 先查任意一个配置的 provider，再查环境变量
  defp from_db_or_env do
    case db_key() do
      {:ok, key} -> {:ok, key}
      :no_db_key -> env_key()
    end
  end

  defp db_key do
    # 测试环境不查 DB（测试用 api_key_override），避免与 DataCase
    # sandbox 的 DBConnection 所有权冲突（owner-exited 竞态）。
    # 生产 release 无 Mix，编译期固化当前环境（用于区分 test / prod）
    if @env == :test do
      :no_db_key
    else
      Enum.find_value(@providers, :no_db_key, fn provider ->
        case TcmEdu.System.ApiKeyConfig
             |> Ash.Query.filter(provider == ^provider)
             |> Ash.Query.limit(1)
             |> Ash.read_one(authorize?: false) do
          {:ok, %{api_key: key}} when is_binary(key) and key != "" -> {:ok, key}
          _ -> nil
        end
      end)
    end
  end

  defp env_key do
    Enum.find_value(env_keys(), {:error, :missing_key}, fn var ->
      case System.get_env(var) do
        key when is_binary(key) and key != "" -> {:ok, key}
        _ -> nil
      end
    end)
  end

  # 注入 ReqLLM 的 alibaba_cn provider，使 Jido agent（model: :qwen 等）也能用同一 key
  # 测试环境不写 OS env，避免并发测试互相污染
  defp ensure_req_llm_key(key) do
    Application.put_env(:req_llm, :alibaba_cn_api_key, key)
    Application.put_env(:req_llm, :dashscope_api_key, key)

    unless @env == :test do
      System.put_env("DASHSCOPE_API_KEY", key)
    end

    :ok
  end

  @doc "默认文本模型（qwen-flash）"
  def text_model, do: Application.get_env(:tcm_edu, TcmEdu.AI, [])[:text_model] || "qwen-flash"

  @doc "视觉模型（qwen3-vl-flash）"
  def vision_model,
    do: Application.get_env(:tcm_edu, TcmEdu.AI, [])[:vision_model] || "qwen3-vl-flash"

  @doc "更强模型（qwen-plus）"
  def plus_model, do: Application.get_env(:tcm_edu, TcmEdu.AI, [])[:plus_model] || "qwen-plus"

  @doc "DashScope OpenAI 兼容 base url"
  def base_url, do: Application.get_env(:tcm_edu, TcmEdu.AI, [])[:base_url] || @base_url

  @doc "请求超时（毫秒）"
  def timeout, do: Application.get_env(:tcm_edu, TcmEdu.AI, [])[:timeout] || 60_000

  @doc "文生图模型（wanx2.1-t2i-turbo）"
  def image_model,
    do: Application.get_env(:tcm_edu, TcmEdu.AI, [])[:image_model] || "wanx2.1-t2i-turbo"

  @doc "DashScope 异步任务 API base（/api/v1）"
  def image_base_url,
    do:
      Application.get_env(:tcm_edu, TcmEdu.AI, [])[:image_base_url] ||
        "https://dashscope.aliyuncs.com/api/v1"

  @doc """
  附加到 Req 请求的可注入选项（通常用于测试：`plug: {Req.Test, Mod}`）。
  生产环境为空列表。
  """
  def req_options, do: Application.get_env(:tcm_edu, TcmEdu.AI, [])[:req_options] || []
end
