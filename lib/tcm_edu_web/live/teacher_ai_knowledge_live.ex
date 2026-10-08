defmodule TcmEduWeb.TeacherAIKnowledgeLive do
  @moduledoc """
  教师端知识库管理 at `/teacher/ai/knowledge`.

  上传教学大纲 / 病例库 / 手册等文档（入库 + 异步向量化 + RAG），也可上传
  图片 / 视频作为资源（存 OSS + 缩略图预览，默认不参与索引/问答）。
  每个源文件可单独开/关「参与索引」「参与问答」，并支持编辑元信息与预览。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.Knowledge.{DocumentExtractor, Ingestion, TenantDoc}
  alias TcmEdu.Workers.TenantDocEmbeddingWorker

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @accepted ~w(.docx .xlsx .pptx .pdf .doc .xls .ppt .odt .ods .odp .txt .md .csv
               .png .jpg .jpeg .gif .webp .bmp .svg .mp4 .mov .webm .avi)

  # 预览最多展示的字符数（文档分片按顺序拼回后）
  @preview_chars 20_000

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher

    Phoenix.PubSub.subscribe(TcmEdu.PubSub, TenantDocEmbeddingWorker.topic(teacher.tenant))

    {:ok,
     socket
     |> assign(:page_title, "知识库")
     |> assign(:page_subtitle, "上传教学大纲、病例库、图片/视频资源，AI 问答依据本校资料作答")
     |> assign(:docs, list_docs(teacher))
     |> assign(:form, doc_form(%{}))
     |> assign(:upload_modal, false)
     |> assign(:editing, nil)
     |> assign(:previewing, nil)
     |> allow_upload(:file,
       accept: @accepted,
       max_entries: 1,
       max_file_size: DocumentExtractor.max_bytes(),
       auto_upload: false
     )}
  end

  @impl true
  def handle_info({:knowledge_docs_event, _type, _payload}, socket) do
    teacher = socket.assigns.current_teacher
    {:noreply, assign(socket, :docs, list_docs(teacher))}
  end

  @impl true
  def handle_event("validate", %{"doc" => params}, socket) do
    {:noreply, assign(socket, :form, doc_form(params))}
  end

  def handle_event("open-upload", _params, socket) do
    {:noreply, assign(socket, :upload_modal, true)}
  end

  def handle_event("close-upload", _params, socket) do
    {:noreply, assign(socket, :upload_modal, false) |> reset_upload()}
  end

  # 上传分流：媒体（图片/视频）→ ingest_media；文档 → ingest
  def handle_event("upload", %{"doc" => params}, socket) do
    teacher = socket.assigns.current_teacher

    result =
      consume_uploaded_entries(socket, :file, fn %{path: path}, entry ->
        binary = File.read!(path)
        title = empty_to_nil(params["title"])
        doc_type = doc_type_atom(params["doc_type"])

        if Ingestion.media?(entry.client_name) do
          kind = if Ingestion.image?(entry.client_name), do: :image, else: :video

          case Ingestion.ingest_media(teacher.tenant, teacher.actor, %{
                 filename: entry.client_name,
                 content: binary,
                 media_kind: kind,
                 title: title,
                 doc_type: doc_type
               }) do
            {:ok, doc} -> {:ok, {:media, doc}}
            {:error, reason} -> {:ok, {:error, reason}}
          end
        else
          case Ingestion.ingest(teacher.tenant, teacher.actor, %{
                 filename: entry.client_name,
                 content: binary,
                 title: title,
                 doc_type: doc_type
               }) do
            {:ok, docs} -> {:ok, {:ingested, docs}}
            {:error, reason} -> {:ok, {:error, reason}}
          end
        end
      end)

    case result do
      [{:ingested, docs}] ->
        {:noreply,
         socket
         |> put_flash(:info, "已入库 #{length(docs)} 个片段，正在生成向量…")
         |> assign(:form, doc_form(%{}))
         |> assign(:upload_modal, false)
         |> assign(:docs, list_docs(teacher))}

      [{:media, doc}] ->
        {:noreply,
         socket
         |> put_flash(:info, "已上传媒体资源《#{doc.title}》")
         |> assign(:form, doc_form(%{}))
         |> assign(:upload_modal, false)
         |> assign(:docs, list_docs(teacher))}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, "入库失败：#{format_reason(reason)}")}

      [] ->
        {:noreply, put_flash(socket, :error, "请先选择要上传的文件")}
    end
  end

  def handle_event("delete-source", %{"source_name" => source_name}, socket) do
    teacher = socket.assigns.current_teacher

    case Ingestion.delete_source(teacher.tenant, teacher.actor, source_name) do
      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(:info, "已删除资料《#{source_name}》（#{count} 个片段）")
         |> assign(:docs, list_docs(teacher))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "删除失败：#{format_reason(reason)}")}
    end
  end

  # ── 索引 / 问答开关 ────────────────────────────────────

  def handle_event("toggle-indexed", %{"source_name" => source_name}, socket) do
    toggle_switch(socket, source_name, :indexed, "索引")
  end

  def handle_event("toggle-in-chat", %{"source_name" => source_name}, socket) do
    toggle_switch(socket, source_name, :in_chat, "问答")
  end

  # ── 编辑 ────────────────────────────────────────────────

  def handle_event("open-edit", %{"source_name" => source_name}, socket) do
    case find_source(socket.assigns.docs, source_name) do
      nil ->
        {:noreply, put_flash(socket, :error, "资料不存在")}

      current ->
        form =
          %{title: current.title, doc_type: current.doc_type}
          |> edit_form()

        {:noreply,
         socket
         |> assign(:editing, %{source_name: source_name, form: form})}
    end
  end

  def handle_event("validate-edit", %{"source" => params}, socket) do
    {:noreply, update_edit_form(socket, params)}
  end

  def handle_event("save-edit", %{"source" => params}, socket) do
    teacher = socket.assigns.current_teacher
    source_name = socket.assigns.editing.source_name

    changeset = edit_changeset(params)
    get = &Ecto.Changeset.get_field(changeset, &1)

    attrs = %{
      title: get.(:title) |> to_string() |> String.trim(),
      doc_type: doc_type_atom(get.(:doc_type))
    }

    case Ingestion.update_source(teacher.tenant, teacher.actor, source_name, attrs) do
      {:ok, count} ->
        {:noreply,
         socket
         |> assign(:editing, nil)
         |> put_flash(:info, "已更新《#{source_name}》（#{count} 片）")
         |> assign(:docs, list_docs(teacher))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "更新失败：#{format_reason(reason)}")}
    end
  end

  def handle_event("close-edit", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  # ── 预览 ────────────────────────────────────────────────

  def handle_event("open-preview", %{"source_name" => source_name}, socket) do
    case find_source(socket.assigns.docs, source_name) do
      nil ->
        {:noreply, put_flash(socket, :error, "资料不存在")}

      current ->
        {:noreply, assign(socket, :previewing, preview_payload(current))}
    end
  end

  def handle_event("close-preview", _params, socket) do
    {:noreply, assign(socket, :previewing, nil)}
  end

  def handle_event("refresh", _params, socket) do
    teacher = socket.assigns.current_teacher
    {:noreply, assign(socket, :docs, list_docs(teacher))}
  end

  # ─── helpers ────────────────────────────────────────────────

  defp toggle_switch(socket, source_name, field, label) do
    teacher = socket.assigns.current_teacher
    current = find_source(socket.assigns.docs, source_name)

    if current do
      attrs = %{field => not Map.get(current, field)}

      case Ingestion.update_source(teacher.tenant, teacher.actor, source_name, attrs) do
        {:ok, count} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             "已#{if(attrs[field], do: "开启", else: "关闭")}《#{source_name}》的#{label}（#{count} 片）"
           )
           |> assign(:docs, list_docs(teacher))}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "操作失败：#{format_reason(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "资料不存在")}
    end
  end

  defp list_docs(teacher) do
    case TenantDoc
         |> Ash.Query.sort(inserted_at: :desc)
         |> Ash.read(actor: teacher.actor, tenant: teacher.tenant) do
      {:ok, docs} -> docs
      _ -> []
    end
  end

  defp find_source(docs, source_name) do
    docs
    |> group_by_source()
    |> Enum.find_value(fn {name, group} -> if name == source_name, do: group, else: nil end)
  end

  defp kb_summary(docs) do
    grouped = group_by_source(docs)

    %{
      sources: length(grouped),
      embedded: grouped |> Enum.flat_map(fn {_, g} -> [g.counts.embedded] end) |> Enum.sum(),
      pending: grouped |> Enum.flat_map(fn {_, g} -> [g.counts.pending] end) |> Enum.sum(),
      failed: grouped |> Enum.flat_map(fn {_, g} -> [g.counts.failed] end) |> Enum.sum()
    }
  end

  # 按 source_name 分组，把同一源文件的所有分片按插入顺序拼回完整文本
  defp group_by_source(docs) do
    docs
    |> Enum.group_by(& &1.source_name)
    |> Enum.map(fn {name, group} ->
      # list_docs 按 inserted_at desc 排序，这里恢复为文档原始顺序
      group = Enum.sort_by(group, & &1.inserted_at)
      first = hd(group)

      status_counts =
        Enum.reduce(group, %{pending: 0, embedded: 0, failed: 0}, fn doc, acc ->
          Map.update(acc, doc.embedding_status, 1, &(&1 + 1))
        end)

      {name,
       %{
         docs: group,
         counts: status_counts,
         total: length(group),
         media_kind: first.media_kind,
         indexed: first.indexed,
         in_chat: first.in_chat,
         title: first.title,
         doc_type: first.doc_type,
         asset_url: first.asset_url,
         thumbnail_url: first.thumbnail_url,
         content: join_chunks(group)
       }}
    end)
    |> Enum.sort_by(fn {name, _} -> name end)
  end

  # 把分片按顺序拼回完整文本（供预览）
  defp join_chunks(group) do
    group
    |> Enum.map(& &1.content)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  # 预览负载：文本 → 完整内容；图片 → 原图；视频 → 播放器
  defp preview_payload(current) do
    case current.media_kind do
      :image ->
        %{source_name: current.title, kind: :image, url: current.asset_url, text: nil}

      :video ->
        %{source_name: current.title, kind: :video, url: current.asset_url, text: nil}

      _ ->
        %{
          source_name: current.title,
          kind: :text,
          url: nil,
          text: truncate_preview(current.content)
        }
    end
  end

  defp truncate_preview(nil), do: nil
  defp truncate_preview(""), do: nil

  defp truncate_preview(text) when is_binary(text) do
    if String.length(text) > @preview_chars do
      String.slice(text, 0, @preview_chars) <> "\n\n…（内容较长，仅显示前 #{@preview_chars} 字）"
    else
      text
    end
  end

  defp doc_type_label(:syllabus), do: "教学大纲"
  defp doc_type_label(:case_library), do: "病例库"
  defp doc_type_label(:handbook), do: "教学手册"
  defp doc_type_label(:other), do: "其他资料"

  defp media_kind_label(:image), do: "图片"
  defp media_kind_label(:video), do: "视频"
  defp media_kind_label(:text), do: "文档"

  defp doc_type_atom(nil), do: :other
  defp doc_type_atom(""), do: :other
  defp doc_type_atom(value), do: String.to_existing_atom(value)

  defp doc_form(params) do
    types = %{title: :string, doc_type: :string}

    {%{doc_type: "other"}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Phoenix.Component.to_form(as: "doc")
  end

  defp edit_form(attrs) do
    %{
      title: attrs[:title] || attrs["title"] || "",
      doc_type: to_string(attrs[:doc_type] || attrs["doc_type"] || "other")
    }
    |> edit_changeset()
    |> Phoenix.Component.to_form(as: "source")
  end

  defp edit_changeset(params) do
    types = %{title: :string, doc_type: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:title])
  end

  defp update_edit_form(socket, params) do
    editing = Map.put(socket.assigns.editing, :form, edit_form_from_params(params))
    assign(socket, :editing, editing)
  end

  defp edit_form_from_params(params) do
    params |> edit_changeset() |> Phoenix.Component.to_form(as: "source")
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value) when is_binary(value), do: String.trim(value)

  defp reset_upload(socket) do
    Enum.each(socket.assigns.uploads.file.entries, fn entry ->
      cancel_upload(socket, :file, entry.ref)
    end)

    socket
  rescue
    _ -> socket
  end

  defp upload_error_to_string(:too_large), do: "文件超过大小限制"
  defp upload_error_to_string(:too_many_files), do: "一次只能上传一个文件"
  defp upload_error_to_string(:not_accepted), do: "不支持的文件类型"
  defp upload_error_to_string(other), do: "上传失败（#{inspect(other)}）"

  defp format_reason(:empty), do: "文档内容为空"
  defp format_reason(:too_large), do: "文件超过大小限制"
  defp format_reason({:unsupported_format, ext}), do: "不支持的格式 #{ext}"
  defp format_reason({:oss, message}), do: "上传失败：#{message}"
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
