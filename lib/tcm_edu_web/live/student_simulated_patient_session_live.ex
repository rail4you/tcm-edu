defmodule TcmEduWeb.StudentSimulatedPatientSessionLive do
  @moduledoc """
  学生端「AI 模拟诊疗」对话页 at `/simulated-patient/sessions/:id`.

  ## 体验

    1. 左侧 SP 档案卡（人设、主诉、性格、关键评分点）
    2. 右侧对话窗口：学生 vs AI 扮演的 SP
    3. 底部输入框：每发一条 → Task.start 异步调 `TcmEdu.AI.SimulatedPatient.respond/2`
    4. 学生主动「结束对话并评分」→ 改 session.status=:completed + 入队 Oban worker
    5. 评分完成后 PubSub 推送，本页面收到事件 → 显示「查看评分」按钮

  ## 路由

      /simulated-patient/sessions/:id                  # 对话
      /simulated-patient/sessions/:id/evaluation        # 评分详情（独立页面）
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query
  require Logger

  alias TcmEdu.AI.SimulatedPatient, as: SPResponder
  alias TcmEdu.SimulatedPatient.{Assignment, Message, Session}
  alias TcmEdu.Workers.SimulatedPatientEvaluationWorker

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @suggestions [
    "您好，请问您哪里不舒服？",
    "这种情况有多久了？",
    "您有没有什么基础疾病？",
    "请告诉我您的作息和饮食情况。"
  ]

  @impl true
  def mount(%{"id" => session_id}, _session, socket) do
    student = socket.assigns.current_student

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        TcmEdu.PubSub,
        SimulatedPatientEvaluationWorker.topic(student.tenant)
      )
    end

    case load_session(session_id, student) do
      {:ok, session} ->
        if session.student_id != student.id do
          {:ok, push_navigate(socket, to: "/simulated-patient")}
        else
          socket =
            socket
            |> assign(:page_title, page_title_for(session))
            |> assign(:page_subtitle, page_subtitle_for(session))
            |> assign(:session, session)
            |> assign(:messages, load_messages(session, student))
            |> assign(:form, message_form())
            |> assign(:suggestions, @suggestions)
            |> assign(:thinking, false)
            |> assign(:run_ref, nil)
            |> assign(:max_turns, max_turns_for(session))
            |> assign(:min_questions, min_questions_for(session))

          {:ok, socket}
        end

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: "/simulated-patient")}
    end
  end

  defp page_title_for(session) do
    "与 #{patient_name(session)} 的问诊对话"
  end

  defp page_subtitle_for(_session) do
    "尽量覆盖教师标注的关键评分点；结束后 AI 会自动评分"
  end

  @impl true
  def handle_event("validate", %{"message" => params}, socket) do
    {:noreply, assign(socket, :form, message_form(params))}
  end

  def handle_event("use-suggestion", %{"content" => content}, socket) do
    {:noreply, assign(socket, :form, message_form(%{"content" => content}))}
  end

  def handle_event("send", %{"message" => %{"content" => content}}, socket) do
    content = String.trim(content || "")

    cond do
      content == "" ->
        {:noreply, socket}

      socket.assigns.session.status != :active ->
        {:noreply, put_flash(socket, :info, "对话已结束")}

      socket.assigns.thinking ->
        {:noreply, put_flash(socket, :info, "AI 正在思考，请稍候")}

      socket.assigns.session.turn_count >= socket.assigns.max_turns ->
        {:noreply, put_flash(socket, :info, "已达最大轮次，请结束对话")}

      true ->
        socket = do_send(socket, content)
        {:noreply, socket}
    end
  end

  def handle_event("end-and-evaluate", _params, socket) do
    student = socket.assigns.current_student
    session = socket.assigns.session

    cond do
      session.turn_count < socket.assigns.min_questions ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "至少需要 #{socket.assigns.min_questions} 轮问诊才建议结束，目前 #{session.turn_count} 轮"
         )}

      session.status != :active ->
        {:noreply, socket}

      true ->
        case end_session(socket, student) do
          {:ok, socket} ->
            {:noreply,
             socket
             |> put_flash(:info, "已结束对话，AI 评分中…完成后会有提示")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "结束失败：#{reason}")}
        end
    end
  end

  def handle_event("abandon", _params, socket) do
    student = socket.assigns.current_student

    case abandon_session(socket, student) do
      {:ok, socket} ->
        {:noreply,
         socket
         |> put_flash(:info, "已放弃本次对话")
         |> push_navigate(to: "/simulated-patient")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "放弃失败：#{reason}")}
    end
  end

  @impl true
  def handle_info({:sp_done, ref, result}, socket) do
    if ref == socket.assigns.run_ref do
      session = socket.assigns.session
      reply = result.reply
      student = socket.assigns.current_student

      case store_message(session, "patient", reply, %{}, student) do
        :ok -> :ok
        err -> Logger.warning("[SPSession] failed to persist patient msg: #{inspect(err)}")
      end

      updated_session = refresh_session(session, socket.assigns.current_student)

      socket =
        socket
        |> assign(:thinking, false)
        |> assign(:run_ref, nil)
        |> assign(:session, updated_session)
        |> assign(
          :messages,
          socket.assigns.messages ++
            [%{role: "patient", content: reply, time: now_time()}]
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:sp_error, ref, message}, socket) do
    if ref == socket.assigns.run_ref do
      {:noreply,
       socket
       |> assign(:thinking, false)
       |> assign(:run_ref, nil)
       |> put_flash(:error, "AI 出错了：#{message}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:simulated_patient_session_event, :evaluation_completed, payload},
        socket
      ) do
    if payload.session_id == socket.assigns.session.id do
      student = socket.assigns.current_student
      session = refresh_session(socket.assigns.session, student)

      {:noreply,
       socket
       |> assign(:session, session)
       |> put_flash(:info, "AI 评分已生成，点击右上角「查看评分」")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:simulated_patient_session_event, :evaluation_failed, payload},
        socket
      ) do
    if payload.session_id == socket.assigns.session.id do
      student = socket.assigns.current_student
      session = refresh_session(socket.assigns.session, student)

      {:noreply,
       socket
       |> assign(:session, session)
       |> put_flash(:error, "AI 评分失败，请稍后在「评分与记录」页点重试")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:simulated_patient_session_event, _, _}, socket), do: {:noreply, socket}

  @impl true
  def handle_params(_params, _uri, socket) do
    socket =
      case socket.assigns.live_action do
        :evaluation -> assign(socket, :live_action_name, :evaluation)
        _ -> assign(socket, :live_action_name, :index)
      end

    {:noreply, socket}
  end

  # ── lifecycle helpers ─────────────────────────────────────

  defp load_session(id, student) do
    Session
    |> Ash.Query.for_read(:read, %{},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.limit(1)
    |> Ash.Query.load([:evaluation])
    |> Ash.read_one(actor: student.actor, tenant: student.tenant)
    |> case do
      {:ok, %Session{} = session} -> {:ok, session}
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :not_found}
  end

  defp refresh_session(%Session{} = session, student) do
    Session
    |> Ash.Query.for_read(:read, %{},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.Query.filter(id == ^session.id)
    |> Ash.Query.limit(1)
    |> Ash.Query.load([:evaluation])
    |> Ash.read_one(actor: student.actor, tenant: student.tenant)
    |> case do
      {:ok, %Session{} = updated} -> updated
      _ -> session
    end
  rescue
    _ -> session
  end

  defp load_messages(%Session{id: session_id}, student) do
    Message
    |> Ash.Query.for_read(:for_session, %{session_id: session_id},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.read(actor: student.actor, tenant: student.tenant)
    |> case do
      {:ok, messages} ->
        Enum.map(messages, fn m ->
          %{
            role: m.role,
            content: m.content,
            time: format_time(m.inserted_at)
          }
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  # ── send ──────────────────────────────────────────────────

  defp do_send(socket, content) do
    session = socket.assigns.session
    student = socket.assigns.current_student
    history = socket.assigns.messages
    lv = self()
    ref = make_ref()

    # 1. 存学生消息（多租户：必须带 tenant / actor，否则创建失败）
    with :ok <- store_message(session, "student", content, %{}, student),
         {:ok, _updated} <-
           session
           |> Ash.Changeset.for_update(:increment_turn, %{},
             actor: student.actor,
             tenant: student.tenant
           )
           |> Ash.update() do
      # 2. 异步调 SP
      Task.start(fn ->
        run_sp(lv, ref, session.patient_snapshot, history, content, socket.assigns.messages)
      end)

      socket
      |> assign(:thinking, true)
      |> assign(:run_ref, ref)
      |> assign(:form, message_form())
      |> assign(
        :messages,
        socket.assigns.messages ++
          [%{role: "student", content: content, time: now_time()}]
      )
      |> refresh_session_assign(student)
    else
      {:error, reason} ->
        Logger.warning("[SPSession] do_send failed: #{inspect(reason)}")
        put_flash(socket, :error, "发送失败：#{reason}，请重试")
    end
  end

  defp refresh_session_assign(socket, student) do
    assign(socket, :session, refresh_session(socket.assigns.session, student))
  end

  defp run_sp(lv_pid, ref, patient_snapshot, _history, student_message, current_messages) do
    # 把刚刚的学生发言也带进 history 让 AI 看到完整上下文
    history_with_current =
      Enum.map(current_messages ++ [%{role: "student", content: student_message}], fn m ->
        %{role: m.role, content: m.content}
      end)

    case SPResponder.respond(
           patient: patient_snapshot,
           history: history_with_current,
           student_message: student_message,
           turn_index: length(current_messages)
         ) do
      {:ok, result} when is_map(result) ->
        reply = Map.get(result, :reply) || Map.get(result, "reply") || ""

        if reply != "" do
          if Process.alive?(lv_pid), do: send(lv_pid, {:sp_done, ref, %{reply: reply}})
        else
          if Process.alive?(lv_pid), do: send(lv_pid, {:sp_error, ref, "AI 返回了空内容"})
        end

      {:error, :missing_key} ->
        if Process.alive?(lv_pid),
          do: send(lv_pid, {:sp_error, ref, "未配置 Qwen API Key，请联系管理员"})

      {:error, reason} ->
        Logger.warning("[SPSession] SP respond failed: #{inspect(reason)}")

        if Process.alive?(lv_pid),
          do: send(lv_pid, {:sp_error, ref, "AI 出错，请稍后重试"})
    end
  rescue
    e ->
      if Process.alive?(lv_pid),
        do: send(lv_pid, {:sp_error, ref, Exception.message(e)})
  end

  defp store_message(%Session{id: session_id}, role, content, metadata, student) do
    Message
    |> Ash.Changeset.for_create(
      :create,
      %{session_id: session_id, role: role, content: content, metadata: metadata},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.create()
    |> case do
      {:ok, _} -> :ok
      {:error, error} -> {:error, ash_message(error)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "存储消息失败，请稍后重试"
  end

  # ── end / abandon ────────────────────────────────────────

  defp end_session(socket, student) do
    session = socket.assigns.session

    with {:ok, ended} <-
           session
           |> Ash.Changeset.for_update(
             :mark_ended,
             %{status: :completed, ended_reason: "student_finished"},
             actor: student.actor,
             tenant: student.tenant
           )
           |> Ash.update(),
         {:ok, pending} <-
           ended
           |> Ash.Changeset.for_update(:set_evaluation_status, %{evaluation_status: :pending},
             actor: student.actor,
             tenant: student.tenant
           )
           |> Ash.update(),
         :ok <- enqueue_evaluation(pending, student) do
      # 把对应的 assignment 标为 completed
      if assignment_id = session.assignment_id do
        case Ash.get(Assignment, assignment_id,
               actor: student.actor,
               tenant: student.tenant
             ) do
          {:ok, %Assignment{} = assignment} ->
            _ =
              assignment
              |> Ash.Changeset.for_update(:mark_completed, %{},
                actor: student.actor,
                tenant: student.tenant
              )
              |> Ash.update()

          _ ->
            :ok
        end
      end

      {:ok, assign(socket, :session, refresh_session(pending, student))}
    end
  end

  defp enqueue_evaluation(%Session{id: session_id}, student) do
    args = %{"tenant" => student.tenant, "session_id" => session_id}

    case SimulatedPatientEvaluationWorker.new(args) |> Oban.insert() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "入队失败：#{inspect(reason)}"}
    end
  end

  defp abandon_session(socket, student) do
    session = socket.assigns.session

    with {:ok, updated} <-
           session
           |> Ash.Changeset.for_update(
             :mark_ended,
             %{status: :abandoned, ended_reason: "abandoned"},
             actor: student.actor,
             tenant: student.tenant
           )
           |> Ash.update() do
      {:ok, assign(socket, :session, updated)}
    end
  end

  # ── form ─────────────────────────────────────────────────

  defp message_form(params \\ %{}) do
    {%{}, %{content: :string}}
    |> Ecto.Changeset.cast(params, [:content])
    |> Ecto.Changeset.validate_required([:content])
    |> Phoenix.Component.to_form(as: "message")
  end

  # ── helpers ───────────────────────────────────────────────

  defp patient_name(%Session{patient_snapshot: snap}) do
    snap["name"] || snap[:name] || "病人"
  end

  defp max_turns_for(%Session{patient_snapshot: snap}) do
    snap["max_turns"] || snap[:max_turns] || 40
  end

  defp min_questions_for(%Session{patient_snapshot: snap}) do
    snap["min_questions"] || snap[:min_questions] || 8
  end

  defp patient_profile(%Session{patient_snapshot: snap}) do
    snap["profile"] || snap[:profile] || %{}
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
  defp format_time(_), do: ""

  defp now_time, do: DateTime.utc_now() |> Calendar.strftime("%H:%M")

  defp format_profile(%{} = profile) do
    profile
    |> Enum.map(fn {k, v} -> "#{k}：#{v}" end)
    |> Enum.join(" · ")
  end

  defp format_profile(_), do: ""

  # ── render ────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.student_shell current_student={@current_student} current_page={:simulated_patient}>
        <%= case @live_action do %>
          <% :evaluation -> %>
            {evaluation_view(assigns)}
          <% _ -> %>
            <div class="mx-auto grid w-full max-w-6xl items-start gap-6 px-4 py-6 sm:px-6 lg:grid-cols-5">
              {patient_panel(assigns)}
              {chat_panel(assigns)}
            </div>
        <% end %>
      </.student_shell>
    </Layouts.app>
    """
  end

  defp evaluation_view(assigns) do
    ~H"""
    <div class="mx-auto flex w-full max-w-4xl flex-col gap-4 px-4 py-6 sm:px-6">
      <div class="flex items-center gap-2 text-sm text-base-content/60">
        <.link navigate="/simulated-patient" class="link link-hover">返回任务列表</.link>
        <span>·</span>
        <.link navigate={"/simulated-patient/sessions/#{@session.id}"} class="link link-hover">
          查看对话
        </.link>
      </div>

      <div class="card border border-base-300 bg-base-100">
        <div class="card-body gap-4 p-4 sm:p-6">
          <div class="flex flex-wrap items-start justify-between gap-2">
            <div>
              <p class="text-lg font-semibold">
                {patient_name(@session)} · AI 评分报告
              </p>
              <p class="text-xs text-base-content/60">
                会话轮次 {@session.turn_count} ·
                {session_status_text(@session.status)} ·
                {format_time(@session.inserted_at)}
              </p>
            </div>
            <span class={["badge badge-soft", evaluation_badge(@session.evaluation_status)]}>
              {evaluation_status_text(@session.evaluation_status)}
            </span>
          </div>

          {eval_card(assigns)}
        </div>
      </div>

      <div class="card border border-base-300 bg-base-100">
        <div class="card-body gap-2 p-4 sm:p-6">
          <p class="font-medium">对话回放</p>
          <div class="flex max-h-96 flex-col gap-2 overflow-y-auto rounded-box border border-base-300 bg-base-200/20 p-3 text-sm">
            <div :for={message <- @messages} class="flex flex-col gap-1">
              <span class={[
                "text-xs",
                message.role == "student" && "text-primary",
                message.role == "patient" && "text-base-content/60"
              ]}>
                {if message.role == "student", do: "医生", else: patient_name(@session)}
                <span :if={message.time != ""}> · {message.time}</span>
              </span>
              <span class={[
                "rounded-2xl px-3 py-1.5",
                message.role == "student" && "bg-primary/10",
                message.role == "patient" && "bg-base-100"
              ]}>
                {message.content}
              </span>
            </div>
            <p :if={@messages == []} class="py-6 text-center text-base-content/60">
              对话为空
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp eval_card(assigns) do
    case assigns.session.evaluation do
      %_{} = evaluation ->
        assigns = assign(assigns, :evaluation, evaluation)

        ~H"""
        <div class="grid items-start gap-4 lg:grid-cols-3">
          <div class="rounded-box border border-base-300 bg-base-200/30 p-4 lg:col-span-1">
            <div class="flex flex-col items-center gap-1 text-center">
              <p class="text-xs text-base-content/60">总分</p>
              <p class="text-5xl font-semibold tabular-nums">
                {Decimal.to_string(@evaluation.total_score, :normal)}
              </p>
              <span class="badge badge-soft badge-success">{grade_label(@evaluation.grade)}</span>
              <p class="mt-2 text-xs text-base-content/60">
                按 rubric {Enum.map_join(@evaluation.rubric_snapshot || %{}, " · ", fn {k, v} -> "#{k} #{v}%" end)}
              </p>
            </div>
          </div>

          <div class="rounded-box border border-base-300 bg-base-200/30 p-4 lg:col-span-2">
            <p class="font-medium">分维度</p>
            <div class="mt-2 grid grid-cols-3 gap-2 text-center">
              <.score_block label="专业度" value={@evaluation.professional_score} />
              <.score_block label="同理心" value={@evaluation.empathy_score} />
              <.score_block label="沟通技巧" value={@evaluation.communication_score} />
            </div>

            <div :if={@evaluation.highlights not in [nil, []]} class="mt-3">
              <p class="text-sm font-medium text-success">亮点</p>
              <ul class="mt-1 list-disc pl-5 text-sm">
                <li :for={h <- @evaluation.highlights}>{h}</li>
              </ul>
            </div>

            <div :if={@evaluation.weaknesses not in [nil, []]} class="mt-3">
              <p class="text-sm font-medium text-warning">不足</p>
              <ul class="mt-1 list-disc pl-5 text-sm">
                <li :for={w <- @evaluation.weaknesses}>{w}</li>
              </ul>
            </div>

            <div :if={@evaluation.key_points_hit not in [nil, []]} class="mt-3">
              <p class="text-sm font-medium text-success">覆盖的评分要点</p>
              <ul class="mt-1 list-disc pl-5 text-sm">
                <li :for={k <- @evaluation.key_points_hit}>{k}</li>
              </ul>
            </div>

            <div :if={@evaluation.key_points_missed not in [nil, []]} class="mt-3">
              <p class="text-sm font-medium text-error">未覆盖的评分要点</p>
              <ul class="mt-1 list-disc pl-5 text-sm">
                <li :for={k <- @evaluation.key_points_missed}>{k}</li>
              </ul>
            </div>

            <details class="mt-3" open>
              <summary class="cursor-pointer text-sm font-medium">综合评语</summary>
              <p class="mt-2 whitespace-pre-line text-sm leading-6">{@evaluation.feedback}</p>
            </details>
          </div>
        </div>
        """

      nil ->
        ~H"""
        <div :if={@session.evaluation_status == :failed} class="alert alert-error alert-soft">
          评分失败：{@session.evaluation_error || "请稍后在「评分与记录」页点重试"}
        </div>
        <div :if={@session.evaluation_status in [:none, :pending, :running]}
          class="alert alert-info alert-soft"
        >
          <span class="loading loading-dots loading-sm" /> 评分尚未完成，请稍后回来查看。
        </div>
        """
    end
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp score_block(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1">
      <span class="text-3xl font-semibold tabular-nums">{@value}</span>
      <span class="text-xs text-base-content/60">{@label}</span>
    </div>
    """
  end

  defp evaluation_badge(:none), do: "badge-ghost"
  defp evaluation_badge(:pending), do: "badge-info"
  defp evaluation_badge(:running), do: "badge-warning"
  defp evaluation_badge(:completed), do: "badge-success"
  defp evaluation_badge(:failed), do: "badge-error"
  defp evaluation_badge(_), do: "badge-ghost"

  defp evaluation_status_text(:none), do: "未评分"
  defp evaluation_status_text(:pending), do: "排队中"
  defp evaluation_status_text(:running), do: "评分中"
  defp evaluation_status_text(:completed), do: "已评分"
  defp evaluation_status_text(:failed), do: "评分失败"
  defp evaluation_status_text(_), do: "未知"

  defp grade_label(:excellent), do: "优秀"
  defp grade_label(:good), do: "良好"
  defp grade_label(:pass), do: "及格"
  defp grade_label(:borderline), do: "边缘"
  defp grade_label(:fail), do: "不及格"
  defp grade_label(_), do: "—"

  defp patient_panel(assigns) do
    ~H"""
    <aside class="lg:col-span-2">
      <div class="card sticky top-4 border border-base-300 bg-base-100">
        <div class="card-body gap-3 p-4 sm:p-6">
          <div class="flex items-center justify-between gap-2">
            <div>
              <p class="text-lg font-semibold">{patient_name(@session)}</p>
              <p :if={@session.patient_snapshot["scenario_title"] || @session.patient_snapshot[:scenario_title]}
                class="text-xs text-base-content/60"
              >
                {@session.patient_snapshot["scenario_title"] || @session.patient_snapshot[:scenario_title]}
              </p>
            </div>
            <span class="badge badge-soft badge-sm">{session_status_text(@session.status)}</span>
          </div>

          <p :if={format_profile(patient_profile(@session)) != ""}
            class="text-xs text-base-content/70"
          >
            {format_profile(patient_profile(@session))}
          </p>

          <details class="rounded-box border border-base-300 bg-base-200/30 p-3 text-sm" open>
            <summary class="cursor-pointer font-medium">主诉</summary>
            <p class="mt-1 whitespace-pre-line">{@session.patient_snapshot["complaint"] || @session.patient_snapshot[:complaint]}</p>
          </details>

          <details class="rounded-box border border-base-300 bg-base-200/30 p-3 text-sm">
            <summary class="cursor-pointer font-medium">病史背景（参考）</summary>
            <p class="mt-1 whitespace-pre-line text-xs">
              {@session.patient_snapshot["history"] || @session.patient_snapshot[:history] || "（无）"}
            </p>
          </details>

          <details class="rounded-box border border-base-300 bg-base-200/30 p-3 text-sm">
            <summary class="cursor-pointer font-medium">性格 / 说话方式</summary>
            <p class="mt-1 text-xs">
              {@session.patient_snapshot["personality"] || @session.patient_snapshot[:personality] || "—"}
              <span class="block text-base-content/60">
                {@session.patient_snapshot["talking_style"] || @session.patient_snapshot[:talking_style] || ""}
              </span>
            </p>
          </details>

          <details class="rounded-box border border-base-300 bg-base-200/30 p-3 text-sm">
            <summary class="cursor-pointer font-medium">教师标注的评分要点</summary>
            <ul class="mt-1 list-disc pl-5 text-xs">
              <li :for={kp <- (@session.patient_snapshot["key_points"] || @session.patient_snapshot[:key_points] || [])}>
                {kp}
              </li>
              <li :if={(@session.patient_snapshot["key_points"] || @session.patient_snapshot[:key_points] || []) == []}
                class="list-none text-base-content/60"
              >
                （无）
              </li>
            </ul>
          </details>

          <p class="text-xs text-base-content/60">
            已问诊 {@session.turn_count} / 最多 {@max_turns} 轮 · 最少建议 {@min_questions} 轮
          </p>
        </div>
      </div>
    </aside>
    """
  end

  defp chat_panel(assigns) do
    ~H"""
    <div class="flex min-h-[28rem] flex-col rounded-box border border-base-300 bg-base-100 lg:col-span-3">
      <div class="flex flex-wrap items-center gap-2 border-b border-base-300 px-4 py-2">
        <span class="badge badge-soft badge-sm">qwen-flash</span>
        <span class="text-sm text-base-content/60">
          病人由 AI 扮演（仅在被问及时揭开病史）
        </span>
        <span :if={@thinking} class="badge badge-soft badge-info badge-sm gap-1">
          <span class="loading loading-dots loading-xs" /> 病人正在思考
        </span>
        <span class="badge badge-ghost badge-sm ms-auto">
          {length(@messages)} 条消息
        </span>
        <.link
          :if={@session.evaluation}
          navigate={"/simulated-patient/sessions/#{@session.id}/evaluation"}
          class="btn btn-ghost btn-sm"
        >
          <.icon name="hero-chart-bar" class="size-4" /> 查看评分
        </.link>
      </div>

      <div id="sp-messages" class="flex flex-1 flex-col gap-3 p-4" aria-live="polite">
        <div
          :if={@messages == [] and !@thinking}
          class="flex flex-col items-center gap-3 rounded-box bg-base-200/10 px-6 py-10 text-center"
        >
          <span class="flex size-16 items-center justify-center rounded-full bg-primary/10 text-primary">
            <.icon name="hero-chat-bubble-left-right" class="size-8" />
          </span>
          <p class="text-base font-semibold">开始问诊</p>
          <p class="text-sm text-base-content/60">可以参考下面这些开场：</p>
          <div class="flex flex-wrap items-center justify-center gap-2">
            <button
              :for={question <- @suggestions}
              type="button"
              phx-click="use-suggestion"
              phx-value-content={question}
              class="btn btn-soft btn-sm"
              disabled={@session.status != :active}
            >
              {question}
            </button>
          </div>
        </div>

        <div
          :for={message <- @messages}
          class={["flex items-start gap-2", message.role == "student" && "flex-row-reverse"]}
        >
          <div class={[
            "flex size-8 shrink-0 items-center justify-center rounded-full",
            message.role == "student" && "bg-neutral text-sm text-neutral-content",
            message.role == "patient" && "bg-primary/10 text-primary"
          ]}>
            {avatar_for(message.role)}
          </div>
          <div class={[
            "flex min-w-0 flex-col gap-1 md:max-w-xl",
            message.role == "student" && "items-end"
          ]}>
            <div class={[
              "w-fit max-w-full rounded-2xl px-4 py-2",
              message.role == "student" && "bg-primary text-primary-content",
              message.role == "patient" && "bg-base-200"
            ]}>
              <p class="whitespace-pre-line text-sm">{message.content}</p>
            </div>
            <p class="text-xs text-base-content/60">
              {if message.role == "student", do: "你（医生）", else: patient_name(@session)}
              <span :if={message.time != ""}> · {message.time}</span>
            </p>
          </div>
        </div>

        <div :if={@thinking} class="flex gap-2">
          <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
            {avatar_for("patient")}
          </div>
          <div class="flex flex-col gap-2 pt-1">
            <div class="skeleton h-4 w-48"></div>
            <div class="skeleton h-4 w-32"></div>
          </div>
        </div>
      </div>

      <div class="sticky bottom-0 rounded-b-box border-t border-base-300 bg-base-100 px-4 py-2">
        <%= if @session.status == :active do %>
          <.form
            for={@form}
            id="sp-form"
            phx-change="validate"
            phx-submit="send"
            class="flex items-end gap-2"
          >
            <div class="min-w-0 flex-1">
              <.input
                field={@form[:content]}
                type="text"
                label="向病人提问或陈述"
                placeholder="例如：您好，您哪里不舒服？"
                autocomplete="off"
                maxlength="2000"
              />
            </div>
            <.button
              type="submit"
              id="sp-send"
              aria-label="发送"
              class="btn-circle btn-primary shrink-0"
              disabled={@thinking}
            >
              <span :if={!@thinking} class="flex items-center justify-center">
                <.icon name="hero-paper-airplane" class="size-5" />
                <span class="sr-only">发送</span>
              </span>
              <span :if={@thinking} class="loading loading-spinner loading-sm" aria-hidden="true" />
            </.button>
          </.form>

          <div class="mt-2 flex items-center justify-between gap-2 text-xs text-base-content/60">
            <span>
              最少 {@min_questions} 轮 / 最多 {@max_turns} 轮 · 已 {@session.turn_count} 轮
            </span>
            <div class="flex items-center gap-2">
              <button
                type="button"
                id="end-eval"
                phx-click="end-and-evaluate"
                class="btn btn-primary btn-sm"
                disabled={@session.turn_count < @min_questions}
              >
                <.icon name="hero-check-circle" class="size-4" />
                结束对话并评分
              </button>
              <button
                type="button"
                id="abandon"
                phx-click="abandon"
                data-confirm="确定放弃本次对话？放弃后无法继续。"
                class="btn btn-ghost btn-sm text-error"
              >
                <.icon name="hero-x-circle" class="size-4" /> 放弃
              </button>
            </div>
          </div>
        <% end %>

        <div :if={@session.status != :active} class="flex flex-col gap-2 py-2">
          <p class="text-sm text-base-content/70">
            <span class="font-medium">{session_status_text(@session.status)}</span>
            <span :if={@session.ended_reason}> · {@session.ended_reason}</span>
          </p>
          <div :if={@session.evaluation_status == :pending or @session.evaluation_status == :running}
            class="alert alert-info alert-soft text-sm"
          >
            <span class="loading loading-dots loading-sm" />
            AI 正在评分，请稍候…
          </div>
          <div :if={@session.evaluation_status == :completed and @session.evaluation}
            class="alert alert-success alert-soft flex items-center justify-between text-sm"
          >
            <span>评分已生成</span>
            <.link
              navigate={"/simulated-patient/sessions/#{@session.id}/evaluation"}
              class="btn btn-primary btn-sm"
            >
              查看评分
            </.link>
          </div>
          <div :if={@session.evaluation_status == :failed}
            class="alert alert-error alert-soft text-sm"
          >
            评分失败：{@session.evaluation_error || "请稍后重试"}
          </div>
          <.link
            navigate="/simulated-patient"
            class="btn btn-ghost btn-sm self-start"
          >
            返回任务列表
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp avatar_for("student") do
    assigns = %{}

    ~H"""
    <span class="text-xs">你</span>
    """
  end

  defp avatar_for("patient") do
    assigns = %{}

    ~H"""
    <.icon name="hero-user" class="size-4" />
    """
  end

  defp session_status_text(:active), do: "进行中"
  defp session_status_text(:completed), do: "已结束"
  defp session_status_text(:abandoned), do: "已放弃"
  defp session_status_text(_), do: "—"
end
