defmodule TcmEdu.Knowledge.Ingestion do
  @moduledoc """
  租户知识库文档入库：提取 → 分片 → 建 `TenantDoc` → 触发向量嵌入。

  教师/租户管理员上传教学大纲、病例库等文件后调用：

      TcmEdu.Knowledge.Ingestion.ingest(tenant, teacher, %{
        filename: "2025 大纲.docx",
        content: file_binary,
        title: "2025 中医基础教学大纲",
        doc_type: :syllabus
      })

  流程：
    1. `TcmEdu.Knowledge.DocumentExtractor.extract/2` 提取纯文本
    2. `chunk/2` 按段落分片（合并到约 `chunk_chars` 字符，超长段落硬切）
    3. 每片建一条 `TenantDoc`（embedding_status = :pending）
    4. 每条 enqueue `TcmEdu.Workers.TenantDocEmbeddingWorker`（Oban 异步嵌入）
  """

  require Logger
  require Ash.Query

  alias TcmEdu.Knowledge.{DocumentExtractor, TenantDoc}
  alias TcmEdu.Workers.TenantDocEmbeddingWorker

  @chunk_chars 1200

  @doc "默认分片目标长度（字符）"
  def chunk_chars, do: Application.get_env(:tcm_edu, __MODULE__, [])[:chunk_chars] || @chunk_chars

  @doc """
  提取文档文本并按段落分片。空文本返回 `[]`。

  返回 chunk 列表（每片非空）。
  """
  @spec chunk(String.t()) :: [String.t()]
  def chunk(text, limit \\ chunk_chars()) when is_binary(text) do
    text
    |> String.trim()
    |> case do
      "" -> []
      trimmed -> do_chunk(trimmed, limit)
    end
  end

  @doc """
  结构感知分片：按标题（h1/h2/h3）把文档切成语义章节块。

  每章标题作为 chunk 首行（`## 标题`），其后段落合并；超长章节回退
  段落级硬切。无标题格式（xlsx 等）退化为 `chunk/2`。

  ## 参数

    * `blocks` — `DocumentExtractor.extract_structured/2` 返回的内容块
    * `limit`  — 目标字符数

  ## 返回

    * `[chunk]`，每片为 `"## 标题\n段落..."` 或纯段落文本
  """
  @spec chunk_blocks([{atom(), String.t()}], pos_integer()) :: [String.t()]
  def chunk_blocks(blocks, limit \\ chunk_chars()) when is_list(blocks) do
    blocks
    |> group_by_heading()
    |> Enum.flat_map(fn %{title: title, paras: paras} ->
      content = section_content(title, paras)

      if String.length(content) <= limit do
        [content]
      else
        do_chunk(content, limit)
      end
    end)
  end

  @doc """
  入库一篇文档。

  ## 参数

    * `tenant` — 租户 schema 名
    * `actor`  — 操作者（User），需 teacher / tenant_admin
    * `attrs`  — `:filename`（必填）、`:content`（必填）、`:title`、`:doc_type`

  ## 返回

    * `{:ok, [%TenantDoc{}]}` — 创建的文档片列表
    * `{:error, reason}` — 提取失败 / 空文档 / 无权
  """
  @spec ingest(String.t(), map(), map()) :: {:ok, [TenantDoc.t()]} | {:error, term()}
  def ingest(tenant, actor, attrs) do
    filename = Map.fetch!(attrs, :filename)
    content = Map.fetch!(attrs, :content)

    with {:ok, blocks} <- DocumentExtractor.extract_structured(content, filename),
         chunks when chunks != [] <- chunk_blocks(blocks) do
      docs =
        Enum.map(chunks, fn chunk ->
          {:ok, doc} =
            TenantDoc.create_tenant_doc(
              %{
                title: Map.get(attrs, :title) || Path.basename(filename),
                doc_type: Map.get(attrs, :doc_type) || :other,
                content: chunk,
                source_name: filename
              },
              actor: actor,
              tenant: tenant
            )

          enqueue_embedding(tenant, doc)
          doc
        end)

      {:ok, docs}
    else
      {:error, reason} -> {:error, reason}
      [] -> {:error, :empty}
    end
  end

  @doc """
  删除某个源文件的所有文档片（并视为整份资料下线）。

  ## 参数

    * `tenant` — 租户 schema 名
    * `actor`  — 操作者（User），需 teacher / tenant_admin
    * `source_name` — 原始文件名

  ## 返回

    * `{:ok, count}` — 删除的文档片数量
    * `{:error, reason}` — 无权限 / 查询失败
  """
  @spec delete_source(String.t(), map(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def delete_source(tenant, actor, source_name) when is_binary(source_name) do
    query =
      TenantDoc
      |> Ash.Query.filter(source_name == ^source_name)
      |> Ash.Query.sort(inserted_at: :asc)

    with {:ok, docs} <- Ash.read(query, actor: actor, tenant: tenant) do
      results =
        Enum.map(docs, fn doc ->
          TenantDoc.destroy_tenant_doc(doc, actor: actor, tenant: tenant)
        end)

      if Enum.all?(results, &(&1 == :ok)) do
        {:ok, length(results)}
      else
        {:error, :destroy_failed}
      end
    end
  end

  @doc """
  批量更新一个源文件的元信息（标题 / 类型 / 索引开关 / 问答开关）。

  适用于教师页编辑资料、开/关「参与索引」「参与问答」。

  ## 返回

    * `{:ok, count}` — 更新的文档片数量
    * `{:error, reason}` — 无权限 / 查询失败
  """
  @spec update_source(String.t(), map(), String.t(), map()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def update_source(tenant, actor, source_name, attrs) when is_binary(source_name) do
    query = Ash.Query.filter(TenantDoc, source_name == ^source_name)

    with {:ok, docs} <- Ash.read(query, actor: actor, tenant: tenant) do
      results =
        Enum.map(docs, fn doc ->
          doc
          |> Ash.Changeset.for_update(:update_source_meta, attrs, actor: actor, tenant: tenant)
          |> Ash.update(actor: actor, tenant: tenant)
        end)

      if Enum.all?(results, &match?({:ok, _}, &1)) do
        {:ok, length(results)}
      else
        {:error, :update_failed}
      end
    end
  end

  @doc """
  入库一篇媒体资源（图片 / 视频）。

  原文件上传到 OSS（`knowledge/tenant/<key>`），建一条 `TenantDoc`：
  `media_kind` 为 :image/:video，`indexed`/`in_chat` 默认 false（不参与向量
  与问答检索，只作为资源浏览）。图片额外生成缩略图 URL（OSS 图片处理 resize）。

  ## 参数

    * `tenant` — 租户 schema 名
    * `actor`  — 操作者（User），需 teacher / tenant_admin
    * `attrs`  — `:filename`（必填）、`:content`（必填）、`:title`、`:doc_type`、
                `:media_kind`（:image/:video，必填）

  ## 返回

    * `{:ok, %TenantDoc{}}`
    * `{:error, reason}`
  """
  @spec ingest_media(String.t(), map(), map()) :: {:ok, TenantDoc.t()} | {:error, term()}
  def ingest_media(tenant, actor, attrs) do
    filename = Map.fetch!(attrs, :filename)
    content = Map.fetch!(attrs, :content)
    media_kind = Map.fetch!(attrs, :media_kind)

    with {:ok, key} <- upload_media(content, filename),
         {:ok, url} <- safe_oss(fn -> TcmEdu.Storage.OSS.signed_url(key) end) do
      attrs =
        %{
          title: Map.get(attrs, :title) || Path.basename(filename),
          doc_type: Map.get(attrs, :doc_type) || :other,
          media_kind: media_kind,
          indexed: false,
          in_chat: false,
          source_name: filename,
          content: "",
          asset_url: url,
          thumbnail_url: thumbnail_signed(key, media_kind)
        }

      case TenantDoc.create_tenant_doc(attrs, actor: actor, tenant: tenant) do
        {:ok, doc} ->
          enqueue_embedding(tenant, doc)
          {:ok, doc}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  文档预览：提取纯文本并截取前 `limit` 字符（简化版预览）。

  非文本资源返回 nil。
  """
  @spec preview(binary(), String.t(), pos_integer()) :: String.t() | nil
  def preview(content, filename, limit \\ 500) do
    if media?(filename) do
      nil
    else
      case DocumentExtractor.extract(content, filename) do
        {:ok, text} when is_binary(text) ->
          if String.length(text) > limit, do: String.slice(text, 0, limit) <> "…", else: text

        _ ->
          nil
      end
    end
  end

  # ── private ───────────────────────────────────────────────

  @image_exts ~w(.png .jpg .jpeg .gif .webp .bmp .svg)
  @video_exts ~w(.mp4 .mov .webm .avi .mkv)

  @doc "是否是媒体资源（图片/视频）"
  def media?(filename) do
    ext = Path.extname(filename) |> String.downcase()
    ext in @image_exts or ext in @video_exts
  end

  @doc "图片扩展名？"
  def image?(filename),
    do: Path.extname(filename) |> String.downcase() |> then(&(&1 in @image_exts))

  defp upload_media(bytes, filename) do
    key = "knowledge/#{System.unique_integer([:positive])}/#{sanitize_filename(filename)}"

    case safe_oss(fn -> TcmEdu.Storage.OSS.upload_bytes(bytes, key) end) do
      {:ok, _url} -> {:ok, key}
      error -> error
    end
  end

  # OSS 凭证缺失时 OSS 模块会 raise（而非返回 {:error, _}）。这里捕获并转成
  # {:error, {:oss, message}}，避免把 LiveView 进程打崩、给前端友好提示。
  defp safe_oss(fun) do
    fun.()
  rescue
    e in RuntimeError -> {:error, {:oss, Exception.message(e)}}
  end

  # 缩略图：图片用 OSS 图片处理 resize 的预签名 URL（处理参数参与签名）；
  # 视频/文档暂无缩略图
  defp thumbnail_signed(key, :image) do
    case safe_oss(fn ->
           TcmEdu.Storage.OSS.signed_url(key, sub_resources: "x-oss-process=image/resize,w_300")
         end) do
      {:ok, url} -> url
      _ -> nil
    end
  end

  defp thumbnail_signed(_key, _), do: nil

  defp sanitize_filename(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[^\w.\-]/u, "_")
  end

  # 把内容块按标题分组为章节：%{title: nil | 最近标题, paras: [String]}
  defp group_by_heading(blocks) do
    blocks
    |> Enum.reduce([], fn block, sections ->
      case block do
        {:heading, text} ->
          [%{title: text, paras: []} | sections]

        {:para, text} ->
          case sections do
            [%{paras: paras} = head | tail] ->
              [%{head | paras: paras ++ [text]} | tail]

            [] ->
              [%{title: nil, paras: [text]}]
          end
      end
    end)
    |> Enum.reverse()
  end

  defp section_content(nil, paras), do: Enum.join(paras, "\n")
  defp section_content(title, []), do: "## " <> title
  defp section_content(title, paras), do: "## " <> title <> "\n" <> Enum.join(paras, "\n")

  defp enqueue_embedding(tenant, %TenantDoc{} = doc) do
    case TenantDocEmbeddingWorker.new(%{"tenant" => tenant, "doc_id" => doc.id})
         |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error("[Knowledge.Ingestion] failed to enqueue embedding: #{inspect(reason)}")
        :ok
    end
  end

  # 按段落合并到 limit；超长段落按字符（Unicode 安全）硬切
  defp do_chunk(text, limit) do
    text
    |> String.split(~r/\n+/, trim: true)
    |> Enum.flat_map(&split_long_para(&1, limit))
    |> Enum.reduce([], fn para, acc ->
      case acc do
        [] ->
          [para]

        [head | tail] ->
          if String.length(head) + 1 + String.length(para) > limit do
            [para, head | tail]
          else
            [head <> "\n" <> para | tail]
          end
      end
    end)
    |> Enum.reverse()
  end

  # 单段超长时按 limit 硬切（String.slice 按 grapheme，安全处理 UTF-8 中文）
  defp split_long_para(para, limit) do
    if String.length(para) <= limit do
      [para]
    else
      do_split_long(para, limit, [])
    end
  end

  defp do_split_long("", _limit, acc), do: Enum.reverse(acc)

  defp do_split_long(rest, limit, acc) do
    piece = String.slice(rest, 0, limit)
    do_split_long(String.slice(rest, limit, String.length(rest)), limit, [piece | acc])
  end
end
