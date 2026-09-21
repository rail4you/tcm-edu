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

  租户知识适配（RAG）：

    * `:tenant` — 租户 schema 名。提供时若 `:knowledge_search` 为真，
      先对 `TcmEdu.Knowledge.TenantDoc` 做语义检索，把 top-k 文档
      注入 system prompt，让 AI 依据本校大纲/病例库回答。

  ## 返回

    * `{:ok, answer}` / `{:error, reason}`（`:missing_key` 表示未配置 Qwen key）
  """
  @spec ask(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ask(message, opts \\ []) when is_binary(message) do
    history = normalize_history(opts[:history] || [])
    model = opts[:model] || :qwen
    system_prompt = opts[:system_prompt] || @system_prompt

    with {:ok, _key} <- AI.api_key() do
      {system_prompt, _references} = rag_context(opts, system_prompt, message)
      messages = history ++ [%{role: "user", content: message}]

      Jido.AI.ask(messages,
        model: model,
        system_prompt: system_prompt,
        max_tokens: opts[:max_tokens] || 4096,
        temperature: opts[:temperature] || 0.7
      )
    end
  end

  @doc """
  带引用溯源的问答：在 `ask/2` 的基础上，额外返回 AI 回答所引用的
  知识库文档（标题列表），便于前端展示「依据本校资料」。

  参数与 `ask/2` 相同。

  ## 返回

    * `{:ok, %{answer: answer, references: [%{title: title}]}}`
    * `{:error, reason}`
  """
  @spec ask_with_references(String.t(), keyword()) ::
          {:ok, %{answer: String.t(), references: [map()]}} | {:error, term()}
  def ask_with_references(message, opts \\ []) when is_binary(message) do
    history = normalize_history(opts[:history] || [])
    model = opts[:model] || :qwen
    system_prompt = opts[:system_prompt] || @system_prompt

    with {:ok, _key} <- AI.api_key() do
      {system_prompt, references} = rag_context(opts, system_prompt, message)
      messages = history ++ [%{role: "user", content: message}]

      case Jido.AI.ask(messages,
             model: model,
             system_prompt: system_prompt,
             max_tokens: opts[:max_tokens] || 4096,
             temperature: opts[:temperature] || 0.7
           ) do
        {:ok, answer} -> {:ok, %{answer: answer, references: references}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # 注入 RAG 上下文：返回 {system_prompt, references}
  defp rag_context(opts, system_prompt, message) do
    if opts[:knowledge_search] && opts[:tenant] do
      query = opts[:query] || message
      top_k = opts[:knowledge_top_k] || 5

      case TcmEdu.Knowledge.search_top_docs(opts[:tenant], query, top_k, in_chat_only: true) do
        {:ok, docs} when docs != [] ->
          {system_prompt <>
             "\n\n## 本校知识库参考资料（如与标准教材冲突，以教材为准）\n\n" <>
             format_docs(docs),
           docs
           |> Enum.map(fn doc -> %{title: doc.title, section: section_of(doc.content)} end)
           |> Enum.uniq_by(&{&1.title, &1.section})}

        _ ->
          {system_prompt, []}
      end
    else
      {system_prompt, []}
    end
  end

  defp format_docs(docs) do
    docs
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {doc, i} ->
      "【资料#{i}：#{doc.title}】\n#{doc.content}"
    end)
  end

  # 从结构化分片的 chunk 首行提取章节名（"## 第一章 阴阳学说"）
  defp section_of(content) do
    case content |> String.split("\n") |> List.first() do
      "## " <> section -> String.trim(section)
      _ -> nil
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
