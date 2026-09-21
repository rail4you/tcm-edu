defmodule TcmEdu.AI.QaChat do
  @moduledoc """
  最普通的 AI 问答服务：Jido AI + ReqLLM + Qwen。

  调用链：`QaChat.ask/2` → `TcmEdu.AI.api_key/0`（DB/环境变量解析 key，
  并注入 `:req_llm` 的 `:alibaba_cn_api_key`）→ `Jido.AI.ask/2`
  （`model: :qwen`，即 `config/config.exs` 中的 `alibaba_cn:qwen-flash`）
  → ReqLLM 直调 DashScope Qwen API。

  历史由调用方按会话从 `chat_messages` 读出（最近 N 条），按
  `[%{role: "user"|"assistant", content: ...}]` 传入，保证多轮连贯。
  """

  alias TcmEdu.AI

  @default_history_limit 20

  @system_prompt """
  你是一位耐心的中医学习助手，用简洁的中文回答问题。
  涉及经络腧穴、方剂、中药时给出准确名称，不确定时明确说明。
  默认使用 Markdown，条理清晰，长度适中。
  """

  @doc """
  纯文本问答（便于单测 / IEx 调试）。

  ## 参数

    * `message` — 本轮用户问题
    * `opts` — `:history`（`[%{role:, content:}]`，默认 `[]`）、
      `:system_prompt`、`:model`（默认 `:qwen`）、`:max_tokens`、`:temperature`

  ## 返回

    * `{:ok, answer}` / `{:error, reason}`（`:missing_key` 表示未配置 Qwen key）
  """
  @spec ask(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ask(message, opts \\ []) when is_binary(message) do
    history = normalize_history(opts[:history] || [])
    model = opts[:model] || :qwen
    system_prompt = opts[:system_prompt] || @system_prompt

    with {:ok, _key} <- AI.api_key() do
      messages = history ++ [%{role: "user", content: message}]

      Jido.AI.ask(messages,
        model: model,
        system_prompt: system_prompt,
        max_tokens: opts[:max_tokens] || 4096,
        temperature: opts[:temperature] || 0.7
      )
    end
  end

  @doc "默认拉取的历史条数（最近 N 条）"
  def default_history_limit, do: @default_history_limit

  @doc """
  规范化历史消息：只保留 user/assistant，裁掉空内容与超长部分。
  暴露出来方便 LiveView 在入库前复用同一规则。
  """
  @spec normalize_history([map()]) :: [map()]
  def normalize_history(history) when is_list(history) do
    history
    |> Enum.flat_map(fn
      %{role: role, content: content} ->
        case {to_string(role), to_string(content) |> String.trim()} do
          {"user", ""} ->
            []

          {"assistant", ""} ->
            []

          {role, trimmed} when role in ["user", "assistant"] ->
            [%{role: role, content: trimmed}]

          _ ->
            []
        end

      _ ->
        []
    end)
    |> Enum.take(-@default_history_limit)
  end

  def normalize_history(_), do: []

  @doc "默认 system prompt（LiveView / 调试共用）"
  def system_prompt, do: @system_prompt
end
