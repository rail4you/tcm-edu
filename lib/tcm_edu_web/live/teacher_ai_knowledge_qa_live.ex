defmodule TcmEduWeb.TeacherAIKnowledgeQaLive do
  @moduledoc """
  知识库问答 at `/teacher/ai/knowledge/qa`.

  左侧列出知识库中「参与问答」的可用资料（已开启索引+问答且完成向量化），
  右侧基于这些资料做 RAG 问答：`TcmEdu.AI.QaChat.ask_with_references/2`
  会先对 `TcmEdu.Knowledge.TenantDoc` 做语义检索，把 top-k 资料注入
  system prompt，回答附带引用来源。

  对话为页面级（不落库），离开页面即清空；需要长期保存的多轮问答请用
  `/teacher/ai/chat`。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query
  require Logger

  alias TcmEdu.AI.QaChat
  alias TcmEdu.Knowledge.TenantDoc
  alias TcmEdu.Workers.TenantDocEmbeddingWorker

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @suggestions [
    "请概括知识库中教学大纲的主要章节",
    "根据病例库，桂枝汤适用于哪些证候？",
    "知识库中有哪些与阴阳五行相关的内容？"
  ]

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher

    Phoenix.PubSub.subscribe(TcmEdu.PubSub, TenantDocEmbeddingWorker.topic(teacher.tenant))

    {:ok,
     socket
     |> assign(:page_title, "知识库问答")
     |> assign(:page_subtitle, "基于本校知识库的 RAG 问答，回答会附带引用的资料")
     |> assign(:suggestions, @suggestions)
     |> assign(:form, qa_form())
     |> assign(:messages, [])
     |> assign(:answering, false)
     |> assign(:run_ref, nil)
     |> assign(:docs, list_docs(teacher))}
  end

  @impl true
  def handle_info({:knowledge_docs_event, _type, _payload}, socket) do
    teacher = socket.assigns.current_teacher
    {:noreply, assign(socket, :docs, list_docs(teacher))}
  end

  def handle_info({:kb_qa_done, ref, result}, socket) do
    if ref == socket.assigns.run_ref do
      answer = result.answer
      references = result.references || []

      {:noreply,
       socket
       |> assign(:answering, false)
       |> assign(:run_ref, nil)
       |> assign(
         :messages,
         socket.assigns.messages ++
           [%{role: "assistant", content: answer, references: references, time: now_time()}]
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:kb_qa_error, ref, message}, socket) do
    if ref == socket.assigns.run_ref do
      {:noreply,
       socket
       |> assign(:answering, false)
       |> assign(:run_ref, nil)
       |> put_flash(:error, message)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate", %{"qa" => params}, socket) do
    {:noreply, assign(socket, :form, qa_form(params))}
  end

  def handle_event("use-suggestion", %{"content" => content}, socket) do
    {:noreply, assign(socket, :form, qa_form(%{"content" => content}))}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, :messages, [])}
  end

  def handle_event("ask", %{"qa" => %{"content" => content}}, socket) do
    content = String.trim(content || "")

    cond do
      content == "" ->
        {:noreply, socket}

      socket.assigns.answering ->
        {:noreply, put_flash(socket, :info, "AI 正在思考，请稍候")}

      true ->
        {:noreply, do_ask(socket, content)}
    end
  end

  def handle_event("refresh", _params, socket) do
    teacher = socket.assigns.current_teacher
    {:noreply, assign(socket, :docs, list_docs(teacher))}
  end

  # ─── helpers ────────────────────────────────────────────────

  defp do_ask(socket, content) do
    teacher = socket.assigns.current_teacher
    history = QaChat.normalize_history(socket.assigns.messages)
    lv = self()
    ref = make_ref()

    Task.start(fn -> run_ask(lv, ref, content, history, teacher.tenant) end)

    socket
    |> assign(:answering, true)
    |> assign(:run_ref, ref)
    |> assign(:form, qa_form())
    |> assign(
      :messages,
      socket.assigns.messages ++ [%{role: "user", content: content, time: now_time()}]
    )
  end

  defp run_ask(lv_pid, ref, content, history, tenant) do
    case QaChat.ask_with_references(content,
           history: history,
           tenant: tenant,
           knowledge_search: true
         ) do
      {:ok, %{answer: answer, references: references}} ->
        if Process.alive?(lv_pid),
          do: send(lv_pid, {:kb_qa_done, ref, %{answer: answer, references: references}})

      {:error, :missing_key} ->
        if Process.alive?(lv_pid),
          do: send(lv_pid, {:kb_qa_error, ref, "未配置 Qwen API Key，请联系管理员在 AI 配置中填写"})

      {:error, reason} ->
        Logger.error("[TeacherAIKnowledgeQaLive] ask failed: #{inspect(reason)}")

        if Process.alive?(lv_pid), do: send(lv_pid, {:kb_qa_error, ref, "请求失败，请稍后重试"})
    end
  rescue
    e ->
      if Process.alive?(lv_pid), do: send(lv_pid, {:kb_qa_error, ref, Exception.message(e)})
  end

  defp list_docs(teacher) do
    case TenantDoc
         |> Ash.Query.sort(inserted_at: :desc)
         |> Ash.read(actor: teacher.actor, tenant: teacher.tenant) do
      {:ok, docs} -> docs
      _ -> []
    end
  end

  # 可用文档：开启索引 + 问答，且至少有一个分片完成向量化
  defp available_docs(docs) do
    docs
    |> group_by_source()
    |> Enum.filter(fn {_name, g} ->
      g.in_chat and g.indexed and g.counts.embedded > 0
    end)
  end

  defp unavailable_count(docs) do
    length(group_by_source(docs)) - length(available_docs(docs))
  end

  defp group_by_source(docs) do
    docs
    |> Enum.group_by(& &1.source_name)
    |> Enum.map(fn {name, group} ->
      first = hd(group)

      counts =
        Enum.reduce(group, %{pending: 0, embedded: 0, failed: 0}, fn doc, acc ->
          Map.update(acc, doc.embedding_status, 1, &(&1 + 1))
        end)

      {name,
       %{
         counts: counts,
         total: length(group),
         media_kind: first.media_kind,
         indexed: first.indexed,
         in_chat: first.in_chat,
         title: first.title,
         doc_type: first.doc_type
       }}
    end)
    |> Enum.sort_by(fn {name, _} -> name end)
  end

  defp qa_form(params \\ %{}) do
    {%{}, %{content: :string}}
    |> Ecto.Changeset.cast(params, [:content])
    |> Ecto.Changeset.validate_required([:content])
    |> Phoenix.Component.to_form(as: "qa")
  end

  defp doc_type_label(:syllabus), do: "教学大纲"
  defp doc_type_label(:case_library), do: "病例库"
  defp doc_type_label(:handbook), do: "教学手册"
  defp doc_type_label(:other), do: "其他资料"

  defp now_time, do: DateTime.utc_now() |> Calendar.strftime("%H:%M")

  defp render_markdown(content) do
    text = to_string(content || "")

    if Code.ensure_loaded?(Earmark) and function_exported?(Earmark, :as_html, 1) do
      case Earmark.as_html(text) do
        {:ok, html, _} -> html
        {:error, html, _} -> html
      end
    else
      text
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
      |> String.replace("\n", "<br>")
    end
  end
end
