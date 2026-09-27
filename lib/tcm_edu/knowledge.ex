defmodule TcmEdu.Knowledge do
  @moduledoc """
  租户知识域：承载院校上传的教学大纲、病例库等文档，并提供向量检索（RAG）。

  第一期只做「租户知识适配」：
    * `TcmEdu.Knowledge.TenantDoc` — 租户知识文档（vectorize 到 `full_text_vector`）
    * 向量搜索（`vector_cosine_distance`），问答时注入 top-k 作为上下文

  真「微调」需要 GPU 训练与模型托管，当前纯 API 调用模式下以 RAG 替代。
  """

  use Ash.Domain,
    otp_app: :tcm_edu,
    extensions: [AshPhoenix]

  resources do
    resource TcmEdu.Knowledge.TenantDoc
  end

  require Ash.Query

  alias TcmEdu.Knowledge.TenantDoc

  @doc """
  该租户是否已有已嵌入的文档（供 UI 决定是否启用知识库检索）。

  返回 boolean。
  """
  @spec has_embedded_docs?(String.t()) :: boolean()
  def has_embedded_docs?(tenant) do
    TenantDoc
    |> Ash.Query.filter(embedding_status == :embedded and indexed == true)
    |> Ash.Query.limit(1)
    |> Ash.exists?(tenant: tenant, authorize?: false)
  end

  @doc """
  语义检索租户知识库，返回与 `query` 最相关的文档（供 RAG 注入）。

  ## 参数

    * `tenant` — 租户 schema 名（如 `"tenant_default"`）
    * `query`  — 检索文本
    * `top_k`  — 返回条数（默认 5）
    * `opts`   — `:in_chat_only`（默认 false）：只检索「问答开关」开启的资源

  ## 返回

    * `{:ok, [%{title: ..., content: ...}]}`
    * `{:error, reason}` — embedding 生成失败 / 未配置 key
  """
  @spec search_top_docs(String.t(), String.t(), pos_integer(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def search_top_docs(tenant, query, top_k \\ 5, opts \\ []) do
    args = %{query: query, k: top_k, in_chat_only: opts[:in_chat_only] || false}

    case TenantDoc.search_tenant_docs(args, tenant: tenant, authorize?: false) do
      {:ok, docs} ->
        {:ok,
         Enum.map(docs, fn doc ->
           %{title: doc.title, content: doc.content}
         end)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
