defmodule TcmEdu.Knowledge.TenantDoc do
  @moduledoc """
  租户知识文档（租户 schema）。

  院校上传的教学大纲 / 病例库 / 手册等文本片段。通过 `vectorize`（AshAi）
  将 `title + content` 嵌入到 `full_text_vector`（pgvector），支撑语义检索。

  Embedding 更新采用 `:manual` 策略：创建/更新文档后由
  `TcmEdu.Workers.TenantDocEmbeddingWorker`（Oban）调用生成的
  `:ash_ai_update_embeddings` action 计算向量，避免同步调 LLM 拖慢写路径。
  """

  use Ash.Resource,
    domain: TcmEdu.Knowledge,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAi],
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  multitenancy do
    strategy :context
  end

  postgres do
    table("tenant_docs")
    repo(TcmEdu.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
      description("文档标题，如「2025 中医基础教学大纲」")
    end

    attribute :doc_type, :atom do
      default(:other)
      constraints(one_of: [:syllabus, :case_library, :handbook, :other])
      public?(true)
      description("文档类型：syllabus 教学大纲 / case_library 病例库 / handbook 手册")
    end

    attribute :content, :string do
      public?(true)
      description("文档文本（分片后的内容）；媒体资源可为空")
    end

    attribute :source_name, :string do
      public?(true)
      description("原始文件名")
    end

    attribute :embedding_status, :atom do
      default(:pending)
      constraints(one_of: [:pending, :embedded, :failed])
      public?(true)
      description("向量化状态：pending 待嵌入 / embedded 已嵌入 / failed 失败")
    end

    attribute :error_message, :string do
      public?(true)
      description("最近一次向量化失败的简要原因")
    end

    attribute :media_kind, :atom do
      default(:text)
      constraints(one_of: [:text, :image, :video])
      public?(true)
      description("资源类型：text 文本文档 / image 图片 / video 视频")
    end

    attribute :indexed, :boolean do
      default(true)
      public?(true)
      description("索引开关：false 则不做向量化、不被检索命中（图片/视频默认 false）")
    end

    attribute :in_chat, :boolean do
      default(true)
      public?(true)
      description("问答开关：false 则该资源不参与 AI 问答检索（只留在知识库供浏览）")
    end

    attribute :asset_url, :string do
      public?(true)
      description("媒体资源（图片/视频）的 OSS URL")
    end

    attribute :thumbnail_url, :string do
      public?(true)
      description("图片缩略图 URL（OSS 图片处理 resize）")
    end

    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)
  end

  vectorize do
    full_text do
      text(fn record ->
        String.trim("#{record.title}\n#{record.content}")
      end)

      # 只有这些属性变化才需要重建向量
      used_attributes([:title, :content])
    end

    # 手动策略：由 Oban worker 在文档写入后调用 :ash_ai_update_embeddings
    strategy :manual

    embedding_model(TcmEdu.AI.QwenEmbeddingModel)
  end

  code_interface do
    define(:list_tenant_docs, action: :read)
    define(:get_tenant_doc, action: :read, get_by: [:id])
    define(:create_tenant_doc, action: :create)
    define(:update_tenant_doc, action: :update)
    define(:destroy_tenant_doc, action: :destroy)
    define(:search_tenant_docs, action: :search)
    define(:mark_embedding_status, action: :mark_embedding_status)
  end

  actions do
    defaults([:read, :update, :destroy])

    create :create do
      primary?(true)

      accept([
        :title,
        :doc_type,
        :content,
        :source_name,
        :media_kind,
        :indexed,
        :in_chat,
        :asset_url,
        :thumbnail_url
      ])

      change(set_attribute(:embedding_status, :pending))
    end

    update :mark_embedding_status do
      require_atomic?(false)
      accept([:embedding_status, :error_message])
    end

    update :update_source_meta do
      require_atomic?(false)
      accept([:title, :doc_type, :indexed, :in_chat])
      description("批量更新一个源文件的元信息（标题/类型/索引开关/问答开关）")
    end

    read :search do
      description("语义检索租户知识库，返回与 query 最相关的 top-k 文档（仅已索引资源）")
      argument(:query, :string, allow_nil?: false)
      argument(:k, :integer, default: 5, constraints: [min: 1, max: 20])
      argument(:in_chat_only, :boolean, default: false)

      prepare(
        before_action(fn query, _context ->
          search_vector = embed_query(query.arguments.query)

          case search_vector do
            {:ok, vector} ->
              query
              |> Ash.Query.filter(
                indexed == true and
                  vector_cosine_distance(full_text_vector, ^vector) < 0.6
              )
              |> maybe_in_chat_filter(query.arguments.in_chat_only)
              |> Ash.Query.sort(
                {calc(vector_cosine_distance(full_text_vector, ^vector), type: :float), :asc}
              )
              |> Ash.Query.limit(query.arguments.k)

            {:error, error} ->
              {:error, error}
          end
        end)
      )
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    # ash_ai 内部更新向量用，worker 以 authorize?: false 调用，兜底允许
    bypass action(:ash_ai_update_embeddings) do
      authorize_if(AshAi.Checks.ActorIsAshAi)
    end

    bypass actor_attribute_equals(:__struct__, TcmEdu.System.SuperAdmin) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
      authorize_if(actor_attribute_equals(:role, :student))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(actor_attribute_equals(:role, :tenant_admin))
      authorize_if(actor_attribute_equals(:role, :teacher))
    end
  end

  defp embed_query(query) do
    TcmEdu.AI.QwenEmbeddingModel.generate([query], [])
    |> case do
      {:ok, [vector]} -> {:ok, vector}
      error -> error
    end
  end

  defp maybe_in_chat_filter(query, true), do: Ash.Query.filter(query, in_chat == true)
  defp maybe_in_chat_filter(query, _), do: query
end
