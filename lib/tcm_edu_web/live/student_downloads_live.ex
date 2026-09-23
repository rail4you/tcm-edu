defmodule TcmEduWeb.StudentDownloadsLive do
  @moduledoc """
  Public 资料下载 (resources/downloads) at `/resources`. Lists the tenant
  knowledge documents (`TcmEdu.Knowledge.TenantDoc`) for the default tenant
  as downloadable study material, matching the storefront downloads mockup
  (keyword search, type badges, download list with a recommended side panel).
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query

  alias TcmEdu.Knowledge.TenantDoc

  on_mount {TcmEduWeb.StudentAuth, :fetch_student}

  @tenant "tenant_default"

  @doc_types [
    {"all", "全部资料"},
    {"syllabus", "教学大纲"},
    {"case_library", "病例库"},
    {"handbook", "手册指南"},
    {"other", "其它资料"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    student = socket.assigns.current_student
    current_tenant = if student, do: student.tenant, else: @tenant

    {:ok,
     socket
     |> assign(:page_title, "资料下载")
     |> assign(:keyword, "")
     |> assign(:doc_type, "all")
     |> assign(:doc_types, @doc_types)
     |> assign(:doc_type_pills, Enum.drop(@doc_types, 1))
     |> assign(:docs, list_docs())
     |> assign(:current_tenant, current_tenant)
     |> assign(:docs_preview?, current_tenant != @tenant)}
  end

  @impl true
  def handle_event("search", %{"keyword" => keyword}, socket) do
    {:noreply, assign(socket, :keyword, String.trim(keyword))}
  end

  def handle_event("filter-type", %{"doc_type" => doc_type}, socket) do
    {:noreply, assign(socket, :doc_type, doc_type)}
  end

  defp list_docs do
    TenantDoc
    |> Ash.Query.for_read(:read, %{}, tenant: @tenant, authorize?: false)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!()
  rescue
    _ -> []
  end

  @doc "Applied filter: keyword + type on top of already-fetched docs."
  def visible(docs, keyword, "all"), do: match_keyword(docs, keyword)

  def visible(docs, keyword, doc_type) do
    docs
    |> Enum.filter(&(&1.doc_type == String.to_atom(doc_type)))
    |> match_keyword(keyword)
  end

  defp match_keyword(docs, ""), do: docs

  defp match_keyword(docs, keyword) do
    haystack = String.downcase(keyword)

    Enum.filter(docs, fn doc ->
      String.contains?(String.downcase("#{doc.title} #{doc.source_name || ""}"), haystack)
    end)
  end

  def doc_type_label(nil), do: "其它资料"
  def doc_type_label(:syllabus), do: "教学大纲"
  def doc_type_label(:case_library), do: "病例库"
  def doc_type_label(:handbook), do: "手册指南"
  def doc_type_label(_), do: "其它资料"

  def doc_type_tone(nil), do: "badge-ghost"
  def doc_type_tone(:syllabus), do: "badge-primary"
  def doc_type_tone(:case_library), do: "badge-secondary"
  def doc_type_tone(:handbook), do: "badge-success"
  def doc_type_tone(_), do: "badge-ghost"

  @doc "Short human label for a media kind."
  def media_label(:image), do: "图片"
  def media_label(:video), do: "视频"
  def media_label(_), do: "文本"

  @doc "A color block shown as the file ext badge, like the mockup's PDF chip."
  def media_tone(:image), do: "from-violet-400 to-indigo-500"
  def media_tone(:video), do: "from-sky-400 to-blue-500"
  def media_tone(_), do: "from-emerald-400 to-green-600"

  def media_ext(:image), do: "IMG"
  def media_ext(:video), do: "VID"
  def media_ext(_), do: "PDF"
end
