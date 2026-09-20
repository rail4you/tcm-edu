defmodule TcmEduWeb.StudentChatLive do
  @moduledoc """
  AI study chat at `/chat` (requires login).

  One session per student (latest reused): messages render as chat
  bubbles, sending runs the same ReAct agent as the JSON API in a
  background Task and streams the answer back grapheme-by-grapheme
  (mirroring the SSE wire format). Long-task lifecycle events arrive
  over PubSub on the same topic the SSE endpoint uses.
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query
  require Logger

  alias TcmEdu.Agents.Registry
  alias TcmEdu.Chat.ChatMessage
  alias TcmEdu.Chat.ChatSession

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @impl true
  def mount(_params, _session, socket) do
    student = socket.assigns.current_student

    if connected?(socket) do
      Phoenix.PubSub.subscribe(TcmEdu.PubSub, "chat:user:#{student.id}:tasks")
    end

    session = get_or_create_session(student)

    {:ok,
     socket
     |> assign(:page_title, "AI 问答")
     |> assign(:chat_session, session)
     |> assign(:messages, list_messages(session))
     |> assign(:form, message_form())
     |> assign(:answering, false)
     |> assign(:draft, "")
     |> assign(:run_ref, nil)
     |> assign(:tasks, [])}
  end

  @impl true
  def handle_event("validate", %{"message" => params}, socket) do
    {:noreply, assign(socket, :form, message_form(params))}
  end

  def handle_event("send", %{"message" => %{"content" => content}}, socket) do
    content = String.trim(content || "")

    cond do
      content == "" ->
        {:noreply, socket}

      socket.assigns.answering ->
        {:noreply, put_flash(socket, :info, "AI 正在思考，请稍候")}

      true ->
        student = socket.assigns.current_student
        session = socket.assigns.chat_session
        lv = self()
        ref = make_ref()

        store_message(session && session.id, "user", content, student)

        Task.start(fn -> run_agent(lv, ref, content) end)

        {:noreply,
         socket
         |> assign(:answering, true)
         |> assign(:draft, "")
         |> assign(:run_ref, ref)
         |> assign(:form, message_form())
         |> assign(:messages, socket.assigns.messages ++ [%{role: "user", content: content}])}
    end
  end

  @impl true
  def handle_info({:chat_delta, ref, text}, socket) do
    if ref == socket.assigns.run_ref do
      {:noreply, update(socket, :draft, &(&1 <> text))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:chat_done, ref, answer, tool_names}, socket) do
    if ref == socket.assigns.run_ref do
      student = socket.assigns.current_student

      store_message(
        socket.assigns.chat_session && socket.assigns.chat_session.id,
        "assistant",
        answer,
        student
      )

      tools_note = if tool_names == [], do: nil, else: "（使用了工具：#{Enum.join(tool_names, "、")}）"

      message = %{role: "assistant", content: answer, tools_note: tools_note}

      {:noreply,
       socket
       |> assign(:answering, false)
       |> assign(:draft, "")
       |> assign(:run_ref, nil)
       |> assign(:messages, socket.assigns.messages ++ [message])}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:chat_error, ref, message}, socket) do
    if ref == socket.assigns.run_ref do
      {:noreply,
       socket
       |> assign(:answering, false)
       |> assign(:draft, "")
       |> assign(:run_ref, nil)
       |> put_flash(:error, "AI 出错了：#{message}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:task_event, type, payload}, socket) do
    tasks = update_tasks(socket.assigns.tasks, type, payload)
    {:noreply, assign(socket, :tasks, tasks)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.student_shell current_student={@current_student} current_page={:chat}>
        <div class="mx-auto flex min-h-[60vh] w-full max-w-4xl flex-col px-4 py-8 sm:px-6">
          <p class="text-2xl font-semibold md:text-3xl">AI 问答</p>
          <p class="mt-1 text-sm text-base-content/60">中医学习问题，随时提问</p>

          <div :if={@tasks != []} class="alert alert-soft alert-info mt-4">
            <.icon name="hero-cog-6-tooth" class="size-5" />
            <p class="text-sm">后台任务进行中：{Enum.map_join(@tasks, "、", & &1.task_name)}</p>
          </div>

          <div id="chat-messages" class="mt-4 flex flex-1 flex-col gap-3" aria-live="polite">
            <div :if={@messages == [] and !@answering} class="rounded-box bg-base-200/30 px-6 py-10 text-center">
              <p class="text-sm text-base-content/60">比如：手太阴肺经有哪些常用腧穴？</p>
            </div>
            <div :for={message <- @messages} class={["chat", message.role == "user" && "chat-end", message.role != "user" && "chat-start"]}>
              <div class={["chat-bubble", message.role == "user" && "chat-bubble-primary"]}>
                <p class="whitespace-pre-line text-sm">{message.content}</p>
                <p :if={Map.get(message, :tools_note)} class="mt-1 text-xs opacity-70">{message.tools_note}</p>
              </div>
            </div>
            <div :if={@answering} class="chat chat-start">
              <div class="chat-bubble">
                <p :if={@draft == ""} class="flex items-center gap-2 text-sm">
                  <span class="loading loading-dots loading-sm" /> 思考中…
                </p>
                <p :if={@draft != ""} class="whitespace-pre-line text-sm">{@draft}<span class="animate-pulse">▍</span></p>
              </div>
            </div>
          </div>

          <.form
            for={@form}
            id="chat-form"
            phx-change="validate"
            phx-submit="send"
            class="sticky bottom-0 mt-4 flex gap-2 bg-base-100 py-2"
          >
            <.input
              field={@form[:content]}
              type="text"
              label="问 AI 一个中医问题"
              placeholder="比如：什么是阴阳五行？"
              autocomplete="off"
              maxlength="2000"
            />
            <.button type="submit" phx-disable-with="发送中..." class="btn-primary mt-auto" disabled={@answering}>
              发送
            </.button>
          </.form>
        </div>
      </.student_shell>
    </Layouts.app>
    """
  end

  # ── session / messages ────────────────────────────────────────

  defp get_or_create_session(student) do
    case ChatSession
         |> Ash.Query.for_read(:read, %{}, actor: student.actor, tenant: student.tenant)
         |> Ash.Query.sort(inserted_at: :desc)
         |> Ash.Query.limit(1)
         |> Ash.read(actor: student.actor, tenant: student.tenant) do
      {:ok, [session | _]} ->
        session

      _ ->
        case ChatSession
             |> Ash.Changeset.for_create(
               :create,
               %{user_id: student.id, agent_name: "chat_agent", title: "学习问答"},
               actor: student.actor,
               tenant: student.tenant
             )
             |> Ash.create() do
          {:ok, session} -> session
          _ -> nil
        end
    end
  rescue
    _ -> nil
  end

  defp list_messages(nil), do: []

  defp list_messages(session) do
    ChatMessage
    |> Ash.Query.filter(session_id == ^session.id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read()
    |> case do
      {:ok, messages} -> Enum.map(messages, &%{role: &1.role, content: &1.content})
      _ -> []
    end
  rescue
    _ -> []
  end

  defp message_form(params \\ %{}) do
    {%{}, %{content: :string}}
    |> Ecto.Changeset.cast(params, [:content])
    |> Ecto.Changeset.validate_required([:content])
    |> Phoenix.Component.to_form(as: "message")
  end

  defp store_message(nil, _role, _content, _student), do: :ok

  defp store_message(session_id, role, content, _student) do
    ChatMessage
    |> Ash.Changeset.for_create(:create, %{session_id: session_id, role: role, content: content})
    |> Ash.create()
  rescue
    _ -> :ok
  end

  # ── background agent ──────────────────────────────────────────

  defp run_agent(lv_pid, ref, user_msg) do
    config = Registry.config("chat_agent") || Registry.fallback()

    result =
      Jido.AI.Reasoning.ReAct.run(user_msg, %{
        model: config.model,
        system_prompt: config.system_prompt,
        tools: config.tools,
        streaming: false,
        max_iterations: config[:max_iterations] || 5
      })

    answer = Map.get(result, :result) || Map.get(result, :answer) || ""
    tool_names = tool_names(result[:trace] || [])

    if Process.alive?(lv_pid) do
      answer
      |> String.graphemes()
      |> Enum.chunk_every(5)
      |> Enum.each(fn chunk ->
        send(lv_pid, {:chat_delta, ref, Enum.join(chunk)})
        Process.sleep(5)
      end)

      send(lv_pid, {:chat_done, ref, answer, tool_names})
    end
  rescue
    e -> if Process.alive?(lv_pid), do: send(lv_pid, {:chat_error, ref, Exception.message(e)})
  end

  defp tool_names(trace) do
    trace
    |> Enum.filter(&(&1.kind in [:tool_started, :tool_completed]))
    |> Enum.map(&(&1.tool_name || ""))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp update_tasks(tasks, :task_completed, %{task_id: id}),
    do: Enum.reject(tasks, &(&1.task_id == id))

  defp update_tasks(tasks, :task_failed, %{task_id: id}),
    do: Enum.reject(tasks, &(&1.task_id == id))

  defp update_tasks(tasks, _type, %{task_id: _} = payload) do
    [Map.take(payload, [:task_id, :task_name, :status, :session_id]) | tasks]
    |> Enum.uniq_by(& &1.task_id)
  end

  defp update_tasks(tasks, _type, _payload), do: tasks
end
