defmodule TcmEduWeb.AdminKnowledgeLive do
  @moduledoc """
  管理端知识库审计视图 at `/admin/knowledge`.

  超管可切换租户查看各机构知识库规模与资源列表（只读审计 + 预览）；
  租户管理员固定查看本机构。不提供编辑/删除（由教师端负责）。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.AdminComponents, only: [admin_shell: 1]

  require Ash.Query

  alias TcmEdu.Knowledge.TenantDoc
  alias TcmEdu.System.Organization

  on_mount {TcmEduWeb.AdminAuth, :ensure_admin}

  # 预览最多展示的字符数（文档分片按顺序拼回后）
  @preview_chars 20_000

  @impl true
  def mount(_params, _session, socket) do
    admin = socket.assigns.current_admin
    tenants = list_tenants(admin)

    tenant =
      if admin.role == "super_admin", do: default_tenant(tenants), else: admin.tenant

    {:ok,
     socket
     |> assign(:page_title, "知识库")
     |> assign(:tenants, tenants)
     |> assign(:tenant, tenant)
     |> assign(:previewing, nil)
     |> load_docs()}
  end

  @impl true
  def handle_event("select-tenant", %{"tenant" => tenant}, socket) do
    {:noreply, socket |> assign(:tenant, tenant) |> assign(:previewing, nil) |> load_docs()}
  end

  def handle_event("open-preview", %{"source_name" => source_name}, socket) do
    case find_source(socket.assigns.docs, source_name) do
      nil -> {:noreply, put_flash(socket, :error, "资料不存在")}
      current -> {:noreply, assign(socket, :previewing, preview_payload(current))}
    end
  end

  def handle_event("close-preview", _params, socket) do
    {:noreply, assign(socket, :previewing, nil)}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load_docs(socket)}
  end

  # ─── helpers ────────────────────────────────────────────────

  defp load_docs(%{assigns: %{tenant: nil}} = socket), do: assign(socket, :docs, [])

  defp load_docs(socket) do
    docs =
      try do
        TenantDoc
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.read(actor: actor(socket), tenant: socket.assigns.tenant, authorize?: true)
        |> case do
          {:ok, docs} -> docs
          _ -> []
        end
      rescue
        _ -> []
      end

    assign(socket, :docs, docs)
  end

  defp group_by_source(docs) do
    docs
    |> Enum.group_by(& &1.source_name)
    |> Enum.map(fn {name, group} ->
      # load_docs 按 inserted_at desc 排序，这里恢复为文档原始顺序
      group = Enum.sort_by(group, & &1.inserted_at)
      first = hd(group)

      counts =
        Enum.reduce(group, %{pending: 0, embedded: 0, failed: 0}, fn doc, acc ->
          Map.update(acc, doc.embedding_status, 1, &(&1 + 1))
        end)

      {name,
       %{
         docs: group,
         counts: counts,
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

  defp summary(grouped) do
    %{
      sources: length(grouped),
      embedded: grouped |> Enum.flat_map(fn {_, g} -> [g.counts.embedded] end) |> Enum.sum(),
      pending: grouped |> Enum.flat_map(fn {_, g} -> [g.counts.pending] end) |> Enum.sum(),
      failed: grouped |> Enum.flat_map(fn {_, g} -> [g.counts.failed] end) |> Enum.sum()
    }
  end

  defp find_source(docs, source_name) do
    docs
    |> group_by_source()
    |> Enum.find_value(fn {name, group} -> if name == source_name, do: group, else: nil end)
  end

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

  defp media_kind_label(:image), do: "图片"
  defp media_kind_label(:video), do: "视频"
  defp media_kind_label(:text), do: "文档"

  defp doc_type_label(:syllabus), do: "教学大纲"
  defp doc_type_label(:case_library), do: "病例库"
  defp doc_type_label(:handbook), do: "教学手册"
  defp doc_type_label(:other), do: "其他资料"

  defp actor(socket), do: socket.assigns.current_admin.actor

  defp list_tenants(%{role: "super_admin", actor: actor}) do
    try do
      Organization.list_organizations!(actor: actor) |> Enum.sort_by(& &1.name)
    rescue
      _ -> []
    end
  end

  defp list_tenants(_), do: []

  defp default_tenant(tenants) do
    case Enum.find(tenants, &(&1.schema_name == "tenant_default")) || List.first(tenants) do
      nil -> nil
      org -> org.schema_name
    end
  end
end
