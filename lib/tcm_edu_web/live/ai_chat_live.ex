defmodule TcmEduWeb.AiChatLive do
  @moduledoc """
  最普通的 AI 问答（Jido AI + ReqLLM + Qwen），教师端与学生端共用。

  功能：

    * 左侧会话列表：新建 / 切换 / 删除，按人隔离（`ChatSession.user_id` policy）
    * 按会话保存聊天历史（`ChatMessage`，`session_id` 关联）
    * 每次问答带上本会话最近 20 条历史，调 `TcmEdu.AI.QaChat.ask/2`
     （Jido AI `model: :qwen` → ReqLLM `alibaba_cn:qwen-flash`）

  路由（`router.ex`）：

    * 教师：`/teacher/ai/chat`（`live_session :teacher`，`current_teacher`）
    * 学生：`/ai-chat`（`live_session :student`，`current_student`）
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]
  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query
  require Logger

  alias TcmEdu.AI.QaChat
  alias TcmEdu.Chat.ChatMessage
  alias TcmEdu.Chat.ChatSession

  @history_limit 20
  @default_title "新的问答"

  @suggestions [
    "手太阴肺经有哪些常用腧穴？",
    "什么是阴阳五行？",
    "风寒感冒从中医角度如何辨证？"
  ]

  @impl true
  def mount(_params, _session, socket) do
    identity = current_identity(socket.assigns)

    if is_nil(identity) do
      {:ok, push_navigate(socket, to: "/login")}
    else
      {sessions, current} =
        case list_sessions(identity) do
          [] ->
            case create_session(identity) do
              {:ok, session} -> {[session], session}
              _ -> {[], nil}
            end

          sessions ->
            {sessions, List.first(sessions)}
        end

      {:ok,
       socket
       |> assign(:page_title, "AI 问答")
       |> assign(:identity, identity)
       |> assign(:suggestions, @suggestions)
       |> assign(:sessions, sessions)
       |> assign(:chat_session, current)
       |> assign(:messages, list_messages(current))
       |> assign(:form, message_form())
       |> assign(:answering, false)
       |> assign(:run_ref, nil)
       |> assign(:knowledge_search, knowledge_search_enabled?(identity))}
    end
  end

  @impl true
  def handle_params(%{"session_id" => id}, _uri, socket) do
    socket =
      case Enum.find(socket.assigns.sessions, &(&1.id == id)) do
        nil -> socket
        session -> select_session(socket, session)
      end

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # ── 会话操作 ────────────────────────────────────────────────

  @impl true
  def handle_event("validate", %{"message" => params}, socket) do
    {:noreply, assign(socket, :form, message_form(params))}
  end

  def handle_event("use-suggestion", %{"content" => content}, socket) do
    {:noreply, assign(socket, :form, message_form(%{"content" => content}))}
  end

  def handle_event("new-session", _params, socket) do
    identity = socket.assigns.identity

    case create_session(identity) do
      {:ok, session} ->
        sessions = [session | socket.assigns.sessions]

        {:noreply,
         socket
         |> assign(:sessions, sessions)
         |> assign(:chat_session, session)
         |> assign(:messages, [])
         |> assign(:form, message_form())
         |> push_patch(to: patch_path(socket, session))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "创建会话失败，请稍后重试")}
    end
  end

  def handle_event("select-session", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.sessions, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      session ->
        {:noreply,
         socket
         |> select_session(session)
         |> push_patch(to: patch_path(socket, session))}
    end
  end

  def handle_event("delete-session", %{"id" => id}, socket) do
    identity = socket.assigns.identity

    case Enum.find(socket.assigns.sessions, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      session ->
        _ = destroy_session(session, identity)
        sessions = Enum.reject(socket.assigns.sessions, &(&1.id == id))

        {sessions, current} =
          case sessions do
            [] ->
              case create_session(identity) do
                {:ok, fresh} -> {[fresh], fresh}
                _ -> {[], nil}
              end

            sessions ->
              {sessions, List.first(sessions)}
          end

        {:noreply,
         socket
         |> assign(:sessions, sessions)
         |> assign(:chat_session, current)
         |> assign(:messages, list_messages(current))
         |> assign(:answering, false)
         |> assign(:run_ref, nil)
         |> push_patch(to: base_path(socket))}
    end
  end

  # ── 发送 ────────────────────────────────────────────────────

  def handle_event("send", %{"message" => %{"content" => content}}, socket) do
    content = String.trim(content || "")

    cond do
      content == "" ->
        {:noreply, socket}

      socket.assigns.answering ->
        {:noreply, put_flash(socket, :info, "AI 正在思考，请稍候")}

      is_nil(socket.assigns.chat_session) ->
        {:noreply, put_flash(socket, :error, "请先新建一个会话")}

      true ->
        socket = do_send(socket, content)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:qa_done, ref, result}, socket) do
    if ref == socket.assigns.run_ref do
      session = socket.assigns.chat_session
      answer = result.answer
      references = result.references || []
      store_message(session, "assistant", answer, %{references: references})
      maybe_rename_session(socket, session)

      {:noreply,
       socket
       |> assign(:answering, false)
       |> assign(:run_ref, nil)
       |> assign(
         :messages,
         socket.assigns.messages ++
           [%{role: "assistant", content: answer, references: references, time: now_time()}]
       )
       |> refresh_sessions()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:qa_error, ref, message}, socket) do
    if ref == socket.assigns.run_ref do
      {:noreply,
       socket
       |> assign(:answering, false)
       |> assign(:run_ref, nil)
       |> put_flash(:error, "AI 出错了：#{message}")}
    else
      {:noreply, socket}
    end
  end

  # ── 渲染 ────────────────────────────────────────────────────

  defp chat_body(assigns) do
    ~H"""
    <%!-- 顶部 hero：与 AI 诊疗 / MDT 共用节奏 --%>
    <div class="mx-auto flex w-full max-w-6xl flex-col gap-4 px-4 py-6 sm:px-6">
      <.ai_chat_hero
        sessions_count={length(@sessions)}
        answering={@answering}
        messages_count={length(@messages)}
        current_title={(@chat_session && @chat_session.title) || "新的问答"}
      />

      <div class={
        [
          "flex flex-col gap-4 md:flex-row",
          teacher_view?(@identity) && "md:h-[calc(100dvh-24rem)] md:min-h-[24rem]",
          !teacher_view?(@identity) && "md:h-[calc(100dvh-220px)] md:min-h-[30rem]"
        ]
      }>
        <%!-- 会话侧栏 --%>
        <aside class="w-full shrink-0 md:w-64" aria-label="会话列表">
          <div class="flex h-full flex-col gap-2 rounded-box border border-base-300 bg-base-100 p-2">
            <button
              type="button"
              id="new-session"
              phx-click="new-session"
              class="btn btn-primary btn-sm w-full"
            >
              <.icon name="hero-plus" class="size-4" /> 新建会话
            </button>
            <ul class="menu w-full gap-1 overflow-y-auto">
              <li class="menu-title flex items-center justify-between">
                <span>会话列表</span>
                <span class="badge badge-soft badge-xs">{length(@sessions)}</span>
              </li>
              <li :for={session <- @sessions} class="group relative">
                <button
                  type="button"
                  id={"session-#{session.id}"}
                  phx-click="select-session"
                  phx-value-id={session.id}
                  class={[
                    "w-full pe-8",
                    session.id == (@chat_session && @chat_session.id) && "bg-primary/10"
                  ]}
                >
                  <span class="flex w-full min-w-0 flex-col items-start gap-0.5">
                    <span class={[
                      "w-full truncate text-left text-sm",
                      session.id == (@chat_session && @chat_session.id) && "font-medium text-primary"
                    ]}>
                      {session.title}
                    </span>
                    <span class="text-xs text-base-content/60">{format_date(session.updated_at)}</span>
                  </span>
                </button>
                <button
                  type="button"
                  id={"delete-session-#{session.id}"}
                  phx-click="delete-session"
                  phx-value-id={session.id}
                  data-confirm="确定删除这个会话及其聊天记录吗？"
                  class="btn btn-ghost btn-xs absolute end-1 top-1/2 z-10 -translate-y-1/2 text-error hover:bg-error/10 md:opacity-0 md:group-hover:opacity-100 md:focus-visible:opacity-100"
                  aria-label={"删除会话 #{session.title}"}
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </li>
            </ul>
            <p :if={@sessions == []} class="px-2 py-6 text-center text-sm text-base-content/60">
              还没有会话，点“新建会话”开始
            </p>
          </div>
        </aside>

        <%!-- 主对话区 --%>
        <div class="flex min-h-[24rem] min-w-0 flex-1 flex-col overflow-hidden rounded-box border border-base-300 bg-base-100">
          <div class="flex flex-wrap items-center gap-2 border-b border-base-300 px-4 py-2">
            <span class="badge badge-soft badge-sm">qwen-flash</span>
            <span class="text-sm text-base-content/60">多轮对话 · 按会话保存历史</span>
            <span :if={@answering} class="badge badge-soft badge-info badge-sm gap-1">
              <span class="loading loading-dots loading-xs" /> 思考中
            </span>
            <span :if={!@answering} class="badge badge-ghost badge-sm ms-auto">
              {length(@messages)} 条消息
            </span>
          </div>

          <div id="qa-messages" class="flex flex-1 flex-col gap-4 overflow-y-auto p-4" aria-live="polite">
            <div
              :if={@messages == [] and !@answering}
              class="flex flex-col items-center gap-4 rounded-box bg-base-200/10 px-6 py-10 text-center"
            >
              <span class="flex size-16 items-center justify-center rounded-full bg-primary/10 text-primary">
                <.icon name="hero-chat-bubble-left-right" class="size-8" />
              </span>
              <div class="flex flex-col gap-1">
                <p class="text-base font-semibold">开始新的问答</p>
                <p class="text-sm text-base-content/60">比如试试下面这些中医学习问题：</p>
              </div>
              <div class="flex flex-wrap items-center justify-center gap-2">
                <button
                  :for={question <- @suggestions}
                  type="button"
                  phx-click="use-suggestion"
                  phx-value-content={question}
                  class="btn btn-soft btn-sm"
                >
                  {question}
                </button>
              </div>
            </div>

            <div
              :for={message <- @messages}
              class={["flex items-start gap-2", message.role == "user" && "flex-row-reverse"]}
            >
              <div
                :if={message.role == "user"}
                class="flex size-8 shrink-0 items-center justify-center rounded-full bg-neutral text-sm text-neutral-content"
              >
                {sender_initial(@identity)}
              </div>
              <div
                :if={message.role != "user"}
                class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary"
              >
                <.icon name="hero-sparkles" class="size-4" />
              </div>
              <div class={[
                "flex min-w-0 flex-col gap-1 md:max-w-xl",
                message.role == "user" && "items-end"
              ]}>
                <div class={[
                  "w-fit max-w-full rounded-2xl px-4 py-2",
                  message.role == "user" && "bg-primary text-primary-content",
                  message.role != "user" && "bg-base-200"
                ]}>
                  <p :if={message.role == "user"} class="whitespace-pre-line text-sm">{message.content}</p>
                  <div
                    :if={message.role != "user"}
                    class="ai-markdown text-sm leading-7 [&_ol]:list-decimal [&_ol]:ps-5 [&_ul]:list-disc [&_ul]:ps-5 [&_code]:rounded [&_code]:bg-base-300/60 [&_code]:px-1 [&_h1]:mt-2 [&_h1]:text-base [&_h1]:font-bold [&_h2]:mt-2 [&_h2]:text-base [&_h2]:font-bold [&_h3]:mt-2 [&_h3]:text-sm [&_h3]:font-bold [&_li]:mt-0.5 [&_p]:my-1 [&_pre]:overflow-x-auto [&_pre]:rounded-lg [&_pre]:bg-base-300/50 [&_pre]:p-2 [&_strong]:font-semibold [&_table]:table [&_td]:border [&_td]:border-base-300 [&_td]:px-2 [&_td]:py-1 [&_th]:border [&_th]:border-base-300 [&_th]:bg-base-300/40 [&_th]:px-2 [&_th]:py-1"
                  >
                    {Phoenix.HTML.raw(render_markdown(message.content))}
                  </div>
                </div>
                <div :if={message.role != "user" and message.references not in [nil, []]}
                  class="flex flex-wrap items-center gap-1"
                >
                  <span class="text-xs text-base-content/60">依据</span>
                  <span
                    :for={ref <- message.references}
                    class="badge badge-soft badge-info badge-sm"
                  >
                    <span class="truncate max-w-40">{ref.section || ref.title}</span>
                  </span>
                </div>
                <p class="text-xs text-base-content/60">
                  {if message.role == "user", do: "你", else: "AI 助手"}
                  <span :if={message.time != ""}> · {message.time}</span>
                </p>
              </div>
            </div>

            <div :if={@answering} class="flex gap-2">
              <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
                <.icon name="hero-sparkles" class="size-4" />
              </div>
              <div class="flex flex-col gap-2 pt-1">
                <div class="skeleton h-4 w-48"></div>
                <div class="skeleton h-4 w-32"></div>
              </div>
            </div>
          </div>

          <div class="sticky bottom-0 z-10 border-t border-base-300 bg-base-100 px-4 py-2">
            <.form
              for={@form}
              id="qa-form"
              phx-change="validate"
              phx-submit="send"
              class="flex items-end gap-2"
            >
              <div class="min-w-0 flex-1">
                <.input
                  field={@form[:content]}
                  type="text"
                  label="问 AI 一个问题"
                  placeholder="比如：什么是阴阳五行？"
                  autocomplete="off"
                  maxlength="2000"
                />
              </div>
              <.button
                type="submit"
                id="qa-send"
                aria-label="发送"
                class="btn-circle btn-primary shrink-0"
                disabled={@answering or is_nil(@chat_session)}
              >
                <span :if={!@answering} class="flex items-center justify-center">
                  <.icon name="hero-paper-airplane" class="size-5" />
                  <span class="sr-only">发送</span>
                </span>
                <span :if={@answering} class="loading loading-spinner loading-sm" aria-hidden="true" />
              </.button>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :sessions_count, :integer, required: true
  attr :answering, :boolean, required: true
  attr :messages_count, :integer, required: true
  attr :current_title, :string, required: true

  defp ai_chat_hero(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 bg-base-100 p-4 sm:p-6">
      <div class="flex flex-wrap items-start gap-4">
        <span class="flex size-12 shrink-0 items-center justify-center rounded-box bg-primary/10 text-primary">
          <.icon name="hero-chat-bubble-left-right" class="size-6" />
        </span>
        <div class="min-w-0 flex-1">
          <h1 class="text-lg font-semibold">AI 问答助手</h1>
          <p class="mt-1 text-sm text-base-content/60">
            基于通义千问的多轮对话，按会话保存历史，方便日后回看
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <span class="badge badge-soft">
            {@sessions_count} 个会话
          </span>
          <span :if={@answering} class="badge badge-soft badge-info gap-1">
            <span class="loading loading-dots loading-xs" /> 思考中
          </span>
          <span :if={!@answering} class="badge badge-soft badge-ghost">
            {@messages_count} 条消息
          </span>
        </div>
      </div>
      <p class="mt-3 truncate text-xs text-base-content/60">
        当前会话：<span class="font-medium text-base-content/80">{@current_title}</span>
      </p>
    </div>
    """
  end

  # ── 身份 / 路径 ─────────────────────────────────────────────

  # 知识库检索：仅当租户已有已嵌入文档时启用（避免每条问题都白花 embedding 费用）
  defp knowledge_search_enabled?(%{tenant: tenant}) when is_binary(tenant) do
    TcmEdu.Knowledge.has_embedded_docs?(tenant)
  rescue
    _ -> false
  end

  defp knowledge_search_enabled?(_), do: false

  defp current_identity(assigns) do
    Map.get(assigns, :current_student) || Map.get(assigns, :current_teacher)
  end

  defp teacher_view?(%{role: role}), do: role in ["teacher", "tenant_admin"]
  defp teacher_view?(_), do: false

  defp base_path(%{assigns: %{identity: identity}}) do
    if teacher_view?(identity), do: "/teacher/ai/chat", else: "/ai-chat"
  end

  defp patch_path(socket, session) do
    base_path(socket) <> "?session_id=#{session.id}"
  end

  # ── 会话读写 ────────────────────────────────────────────────

  defp list_sessions(identity) do
    ChatSession
    |> Ash.Query.for_read(:read, %{}, actor: identity.actor)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(actor: identity.actor)
    |> case do
      {:ok, sessions} -> sessions
      _ -> []
    end
  rescue
    _ -> []
  end

  defp create_session(identity) do
    ChatSession
    |> Ash.Changeset.for_create(
      :create,
      %{user_id: identity.id, agent_name: "qa_agent", title: @default_title},
      actor: identity.actor
    )
    |> Ash.create()
  end

  defp destroy_session(session, identity) do
    Ash.destroy(session, actor: identity.actor)
  rescue
    _ -> :ok
  end

  defp select_session(socket, session) do
    socket
    |> assign(:chat_session, session)
    |> assign(:messages, list_messages(session))
    |> assign(:form, message_form())
    |> assign(:answering, false)
    |> assign(:run_ref, nil)
  end

  defp refresh_sessions(socket) do
    sessions = list_sessions(socket.assigns.identity)
    current_id = socket.assigns.chat_session && socket.assigns.chat_session.id
    current = Enum.find(sessions, &(&1.id == current_id)) || socket.assigns.chat_session
    assign(socket, :sessions, sessions) |> assign(:chat_session, current)
  end

  defp list_messages(nil), do: []

  defp list_messages(session) do
    ChatMessage
    |> Ash.Query.for_read(:for_session, %{session_id: session.id})
    |> Ash.Query.limit(@history_limit * 5)
    |> Ash.read()
    |> case do
      {:ok, messages} ->
        Enum.map(messages, fn msg ->
          %{
            role: msg.role,
            content: msg.content,
            references: metadata_references(msg.metadata),
            time: format_time(msg.inserted_at)
          }
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  # jsonb 解码后 metadata 的 key 是 string（存的时候是 atom key），统一归一化
  defp metadata_references(nil), do: []

  defp metadata_references(%{"references" => refs}) when is_list(refs),
    do: normalize_refs(refs)

  defp metadata_references(%{references: refs}) when is_list(refs), do: normalize_refs(refs)
  defp metadata_references(_), do: []

  defp normalize_refs(refs) do
    Enum.map(refs, fn
      %{"title" => title} = ref -> %{title: title, section: Map.get(ref, "section")}
      %{title: title} = ref -> %{title: title, section: Map.get(ref, :section)}
      _ -> %{}
    end)
  end

  # ── 发送 ────────────────────────────────────────────────────

  defp do_send(socket, content) do
    session = socket.assigns.chat_session
    history = socket.assigns.messages |> QaChat.normalize_history() |> Enum.take(-@history_limit)
    tenant = socket.assigns.identity.tenant
    knowledge_search = socket.assigns.knowledge_search
    lv = self()
    ref = make_ref()

    store_message(session, "user", content)
    maybe_rename_session(socket, session, content)

    Task.start(fn -> run_qa(lv, ref, content, history, tenant, knowledge_search) end)

    socket
    |> assign(:answering, true)
    |> assign(:run_ref, ref)
    |> assign(:form, message_form())
    |> assign(
      :messages,
      socket.assigns.messages ++ [%{role: "user", content: content, time: now_time()}]
    )
    |> refresh_sessions()
  end

  defp run_qa(lv_pid, ref, content, history, tenant, knowledge_search) do
    case QaChat.ask_with_references(content,
           history: history,
           tenant: tenant,
           knowledge_search: knowledge_search
         ) do
      {:ok, %{answer: answer, references: references}} ->
        if Process.alive?(lv_pid),
          do: send(lv_pid, {:qa_done, ref, %{answer: answer, references: references}})

      {:error, :missing_key} ->
        if Process.alive?(lv_pid),
          do: send(lv_pid, {:qa_error, ref, "未配置 Qwen API Key，请联系管理员在 AI 配置中填写"})

      {:error, reason} ->
        Logger.error("[AiChatLive] qa failed: #{inspect(reason)}")

        if Process.alive?(lv_pid),
          do: send(lv_pid, {:qa_error, ref, "请求失败，请稍后重试"})
    end
  rescue
    e ->
      if Process.alive?(lv_pid),
        do: send(lv_pid, {:qa_error, ref, Exception.message(e)})
  end

  defp store_message(session, role, content, metadata \\ %{})

  defp store_message(nil, _role, _content, _metadata), do: :ok

  defp store_message(session, role, content, metadata) do
    ChatMessage
    |> Ash.Changeset.for_create(:create, %{
      session_id: session.id,
      role: role,
      content: content,
      metadata: metadata
    })
    |> Ash.create()
  rescue
    _ -> :ok
  end

  defp maybe_rename_session(socket, session, first_content \\ nil) do
    if session && session.title in [@default_title, "New Chat", "学习问答"] do
      title =
        (first_content || first_user_message(socket.assigns.messages))
        |> to_string()
        |> String.trim()
        |> String.slice(0, 24)

      if title != "" do
        session
        |> Ash.Changeset.for_update(:rename, %{title: title},
          actor: socket.assigns.identity.actor
        )
        |> Ash.update()
      end
    end
  rescue
    _ -> :ok
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
  defp format_time(_), do: ""

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M")
  defp format_date(_), do: ""

  defp now_time, do: DateTime.utc_now() |> Calendar.strftime("%H:%M")

  defp sender_initial(%{name: name}) when is_binary(name) do
    name |> String.trim() |> String.first() |> String.upcase()
  end

  defp sender_initial(_), do: "你"

  defp first_user_message(messages) do
    messages
    |> Enum.find(&(&1.role == "user"))
    |> case do
      %{content: content} -> content
      _ -> ""
    end
  end

  defp render_markdown(content) do
    text = to_string(content || "")

    if Code.ensure_loaded?(Earmark) and function_exported?(Earmark, :as_html, 1) do
      case Earmark.as_html(text) do
        {:ok, html, _} -> html
        {:error, html, _} -> html
      end
    else
      # server 尚未重启加载新依赖时的纯文本兜底，避免页面崩溃
      text
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
      |> String.replace("\n", "<br>")
    end
  end

  defp message_form(params \\ %{}) do
    {%{}, %{content: :string}}
    |> Ecto.Changeset.cast(params, [:content])
    |> Ecto.Changeset.validate_required([:content])
    |> Phoenix.Component.to_form(as: "message")
  end
end
