defmodule TcmEdu.Workers.TenantDocEmbeddingWorker do
  @moduledoc """
  Oban worker：为租户知识文档计算向量嵌入。

  文档创建/更新后由调用方 enqueue（`TenantDoc` 写入处），worker 内加载文档，
  调生成的 `:ash_ai_update_embeddings` action（内部调 `TcmEdu.AI.QwenEmbeddingModel`
  生成 `full_text_vector`），成功后把 `embedding_status` 置为 `:embedded`。

  每次状态变更向 `knowledge_docs:<tenant>` 广播
  `{:knowledge_docs_event, :doc_embedded | :doc_failed, payload}`，
  教师端知识库页订阅后自动刷新列表（无需手动点刷新）。

  ## 用法

      TcmEdu.Workers.TenantDocEmbeddingWorker.new(%{
        "tenant" => "tenant_default",
        "doc_id" => doc_id
      })
      |> Oban.insert()
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Ash.Query

  alias TcmEdu.Knowledge.TenantDoc

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"doc_id" => doc_id} = args}) do
    tenant = args["tenant"] || "tenant_default"

    with {:ok, doc} <- load_doc(doc_id, tenant) do
      cond do
        # 非文本文档（图片/视频）或索引关闭：不向量化
        doc.media_kind != :text or not doc.indexed ->
          finish(doc, tenant, :embedded, nil)

        true ->
          case run_embedding(doc, tenant) do
            :ok -> finish(doc, tenant, :embedded, nil)
            {:error, _reason} -> finish(doc, tenant, :failed, safe_message())
          end
      end
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def perform(%Oban.Job{args: args}) do
    {:error, "missing doc_id in args: #{inspect(args)}"}
  end

  @doc "知识库文档状态广播的 PubSub topic。"
  def topic(tenant), do: "knowledge_docs:#{tenant}"

  defp load_doc(id, tenant) do
    case TenantDoc
         |> Ash.Query.filter(id == ^id)
         |> Ash.Query.limit(1)
         |> Ash.read_one(tenant: tenant, authorize?: false) do
      {:ok, %TenantDoc{} = doc} -> {:ok, doc}
      other -> {:error, "tenant_doc not found: #{inspect(other)}"}
    end
  end

  # 调用 ash_ai 生成的 :ash_ai_update_embeddings action 重新计算向量
  defp run_embedding(%TenantDoc{} = doc, tenant) do
    case doc
         |> Ash.Changeset.for_update(:ash_ai_update_embeddings, %{})
         |> Ash.update(tenant: tenant, authorize?: false) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp finish(%TenantDoc{} = doc, tenant, status, message) do
    attrs = %{embedding_status: status, error_message: message}

    case doc
         |> Ash.Changeset.for_update(:mark_embedding_status, attrs)
         |> Ash.update(tenant: tenant, authorize?: false) do
      {:ok, updated} ->
        broadcast(
          tenant,
          if(status == :embedded, do: :doc_embedded, else: :doc_failed),
          payload(updated)
        )

        case status do
          :embedded -> :ok
          :failed -> {:error, "embedding failed"}
        end

      {:error, error} ->
        {:error, inspect(error)}
    end
  end

  defp broadcast(tenant, type, payload) do
    Phoenix.PubSub.broadcast(TcmEdu.PubSub, topic(tenant), {:knowledge_docs_event, type, payload})
    :ok
  rescue
    _ -> :ok
  end

  defp payload(%TenantDoc{} = doc) do
    %{
      doc_id: doc.id,
      source_name: doc.source_name,
      embedding_status: doc.embedding_status
    }
  end

  # 不要返回 provider 原始错误（可能含 Authorization header / body 细节）
  defp safe_message, do: "embedding generation failed"
end
