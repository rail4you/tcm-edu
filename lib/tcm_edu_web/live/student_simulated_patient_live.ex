defmodule TcmEduWeb.StudentSimulatedPatientLive do
  @moduledoc """
  学生端「AI 模拟诊疗」入口 at `/simulated-patient`.

  三级路由：

    * `/simulated-patient`                           — 任务列表（assignments + 历史 sessions）
    * `/simulated-patient/sessions/:id`              — 与标准化病人对话
    * `/simulated-patient/sessions/:id/evaluation`   — 查看 AI 评分详情

  学生可以：

    * 在「分配管理」中看到教师布置的病人任务，开始 / 继续对话；
    * 与 AI 扮演的病人对话（流式按回合生成，最多 `max_turns` 轮）；
    * 主动结束对话，触发 Oban 后台评分；评分完成通过 PubSub 实时刷新；
    * 查看自己的历史评分（按维度分数、亮点 / 不足 / 评语展开）。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.StudentComponents, only: [student_shell: 1]

  require Ash.Query
  require Logger

  alias TcmEdu.SimulatedPatient.{
    Assignment,
    Evaluation,
    Patient,
    Session
  }

  alias TcmEdu.Workers.SimulatedPatientEvaluationWorker

  on_mount {TcmEduWeb.StudentAuth, :ensure_student}

  @impl true
  def mount(_params, _session, socket) do
    student = socket.assigns.current_student

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        TcmEdu.PubSub,
        SimulatedPatientEvaluationWorker.topic(student.tenant)
      )
    end

    socket =
      socket
      |> assign(:page_title, "AI 模拟诊疗")
      |> assign(:page_subtitle, "与标准化病人对话，结束后 AI 会从专业度、同理心、沟通技巧三个维度评分")
      |> load_assignments()
      |> load_sessions()

    {:ok, socket}
  end

  @impl true
  def handle_event("start-assignment", %{"id" => assignment_id}, socket) do
    student = socket.assigns.current_student

    case Enum.find(socket.assigns.assignments, &(&1.id == assignment_id)) do
      %Assignment{} = assignment ->
        with {:ok, session} <- ensure_session(socket, assignment, student) do
          {:noreply,
           socket
           |> push_navigate(to: "/simulated-patient/sessions/#{session.id}")}
        else
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "无法开始任务：#{reason}")}
        end

      nil ->
        {:noreply, put_flash(socket, :error, "任务不存在或已被撤销")}
    end
  end

  @impl true
  def handle_info(
        {:simulated_patient_session_event, :evaluation_completed, payload},
        socket
      ) do
    if payload.student_id == socket.assigns.current_student.id do
      {:noreply,
       socket
       |> load_sessions()
       |> put_flash(:info, "AI 评分已生成")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:simulated_patient_session_event, :evaluation_failed, payload},
        socket
      ) do
    if payload.student_id == socket.assigns.current_student.id do
      {:noreply,
       socket
       |> load_sessions()
       |> put_flash(:error, "AI 评分失败，请稍后重试")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:simulated_patient_session_event, _, _}, socket) do
    {:noreply, load_sessions(socket)}
  end

  # ── loading ───────────────────────────────────────────────

  defp load_assignments(socket) do
    student = socket.assigns.current_student

    assignments =
      try do
        Assignment
        |> Ash.Query.for_read(:for_student, %{student_id: student.id},
          actor: student.actor,
          tenant: student.tenant
        )
        |> Ash.Query.load([:patient])
        |> Ash.read!()
      rescue
        _ -> []
      end

    assign(socket, :assignments, assignments)
  end

  defp load_sessions(socket) do
    student = socket.assigns.current_student

    sessions =
      try do
        Session
        |> Ash.Query.for_read(:for_student, %{student_id: student.id},
          actor: student.actor,
          tenant: student.tenant
        )
        |> Ash.Query.load([:patient, :evaluation])
        |> Ash.read!()
      rescue
        _ -> []
      end

    assign(socket, :sessions, sessions)
  end

  # ── session creation ──────────────────────────────────────

  # 优先复用已有的 active session；若没有则新建。
  defp ensure_session(socket, %Assignment{} = assignment, _student) do
    student = socket.assigns.current_student

    active =
      Enum.find(socket.assigns.sessions, fn s ->
        s.assignment_id == assignment.id and s.status == :active
      end)

    case active do
      %Session{} = s ->
        {:ok, s}

      nil ->
        patient =
          Ash.get!(Patient, assignment.patient_id,
            actor: student.actor,
            tenant: student.tenant
          )

        snapshot = patient_snapshot(patient)

        with {:ok, session} <-
               Session
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   assignment_id: assignment.id,
                   patient_id: patient.id,
                   student_id: student.id,
                   patient_snapshot: snapshot,
                   status: :active,
                   evaluation_status: :none
                 },
                 actor: student.actor,
                 tenant: student.tenant
               )
               |> Ash.create() do
          # 同时把 assignment 标记为进行中
          _ =
            assignment
            |> Ash.Changeset.for_update(:mark_in_progress, %{},
              actor: student.actor,
              tenant: student.tenant
            )
            |> Ash.update()

          {:ok, session}
        end
    end
  end

  defp patient_snapshot(%Patient{} = patient) do
    %{
      "id" => patient.id,
      "name" => patient.name,
      "scenario_title" => patient.scenario_title,
      "profile" => patient.profile || %{},
      "complaint" => patient.complaint,
      "history" => patient.history,
      "personality" => patient.personality,
      "talking_style" => patient.talking_style,
      "key_points" => patient.key_points || [],
      "rubric" => patient.rubric || %{},
      "difficulty" => patient.difficulty,
      "min_questions" => patient.min_questions,
      "max_turns" => patient.max_turns
    }
  end

  # ── render ────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} shell={:admin}>
      <.student_shell current_student={@current_student} current_page={:simulated_patient}>
        <div class="mx-auto flex w-full max-w-6xl flex-col gap-6 px-4 py-6 sm:px-6">
          {tasks_section(assigns)}
          {history_section(assigns)}
        </div>
      </.student_shell>
    </Layouts.app>
    """
  end

  defp tasks_section(assigns) do
    ~H"""
    <div class="card border border-base-300 bg-base-100">
      <div class="card-body gap-3 p-4 sm:p-6">
        <div class="flex items-center justify-between gap-2">
          <p class="font-medium">教师布置的任务</p>
          <span class="badge badge-soft badge-sm">{length(@assignments)} 条</span>
        </div>

        <p :if={@assignments == []} class="py-6 text-center text-sm text-base-content/60">
          目前没有分配给你的模拟诊疗任务。
        </p>

        <div :if={@assignments != []} class="grid items-start gap-3 md:grid-cols-2">
          <article
            :for={assignment <- @assignments}
            id={"assignment-#{assignment.id}"}
            class="card border border-base-300 bg-base-100"
          >
            <div class="card-body gap-2 p-4">
              <p class="text-base font-semibold">{patient_name_for(assignment)}</p>
              <p :if={patient_scenario_title(assignment)} class="text-xs text-base-content/60">
                {patient_scenario_title(assignment)}
              </p>
              <p class="line-clamp-3 text-sm">
                <span class="text-base-content/60">主诉：</span>
                {patient_complaint(assignment) || "—"}
              </p>
              <div class="mt-1 flex flex-wrap items-center gap-2 text-xs text-base-content/60">
                <span class="badge badge-soft badge-sm">{assignment_status_text(assignment.status)}</span>
                <span :if={assignment.deadline}>
                  截止 {Calendar.strftime(assignment.deadline, "%m-%d %H:%M")}
                </span>
              </div>
              <p :if={assignment.notes} class="text-xs">{assignment.notes}</p>
              <div class="mt-1 flex justify-end">
                <button
                  type="button"
                  id={"start-#{assignment.id}"}
                  phx-click="start-assignment"
                  phx-value-id={assignment.id}
                  class="btn btn-primary btn-sm"
                >
                  <.icon name="hero-play" class="size-4" /> 开始 / 继续
                </button>
              </div>
            </div>
          </article>
        </div>
      </div>
    </div>
    """
  end

  defp history_section(assigns) do
    ~H"""
    <div class="card border border-base-300 bg-base-100">
      <div class="card-body gap-3 p-4 sm:p-6">
        <div class="flex items-center justify-between gap-2">
          <p class="font-medium">历史对话与评分</p>
          <span class="badge badge-soft badge-sm">{length(@sessions)} 条</span>
        </div>

        <p :if={@sessions == []} class="py-6 text-center text-sm text-base-content/60">
          还没有完成的对话。开始一个任务后会出现在这里。
        </p>

        <div :if={@sessions != []} class="grid items-start gap-3 md:grid-cols-2">
          <article
            :for={session <- @sessions}
            id={"session-row-#{session.id}"}
            class="card border border-base-300 bg-base-100"
          >
            <div class="card-body gap-2 p-4">
              <div class="flex items-start justify-between gap-2">
                <div>
                  <p class="text-base font-semibold">
                    {session.patient_snapshot["name"] || session.patient_snapshot[:name]}
                  </p>
                  <p :if={session.patient_snapshot["scenario_title"] || session.patient_snapshot[:scenario_title]}
                    class="text-xs text-base-content/60"
                  >
                    {session.patient_snapshot["scenario_title"] || session.patient_snapshot[:scenario_title]}
                  </p>
                </div>
                <span class={[
                  "badge badge-soft",
                  evaluation_badge(session.evaluation_status)
                ]}>
                  {evaluation_status_text(session.evaluation_status)}
                </span>
              </div>

              <p class="text-xs text-base-content/60">
                轮次 {session.turn_count} ·
                {session_status_text(session.status)} ·
                {format_date(session.inserted_at)}
              </p>

              {eval_summary(session)}

              <div class="mt-1 flex flex-wrap items-center gap-2">
                <.link
                  :if={session.status == :active}
                  navigate={"/simulated-patient/sessions/#{session.id}"}
                  class="btn btn-primary btn-sm"
                >
                  <.icon name="hero-play" class="size-4" /> 继续对话
                </.link>
                <.link
                  :if={session.status != :active}
                  navigate={"/simulated-patient/sessions/#{session.id}"}
                  class="btn btn-ghost btn-sm"
                >
                  <.icon name="hero-eye" class="size-4" /> 查看对话
                </.link>
                <.link
                  :if={session.evaluation}
                  navigate={"/simulated-patient/sessions/#{session.id}/evaluation"}
                  class="btn btn-ghost btn-sm"
                >
                  <.icon name="hero-chart-bar" class="size-4" /> 评分详情
                </.link>
              </div>
            </div>
          </article>
        </div>
      </div>
    </div>
    """
  end

  defp eval_summary(session) do
    case session.evaluation do
      %Evaluation{} = evaluation ->
        assigns = %{evaluation: evaluation}

        ~H"""
        <div class="rounded-box border border-base-300 bg-base-200/30 p-3 text-sm">
          <div class="grid grid-cols-3 gap-2 text-center">
            <span class="flex flex-col items-center">
              <span class="text-2xl font-semibold tabular-nums">{@evaluation.professional_score}</span>
              <span class="text-xs text-base-content/60">专业度</span>
            </span>
            <span class="flex flex-col items-center">
              <span class="text-2xl font-semibold tabular-nums">{@evaluation.empathy_score}</span>
              <span class="text-xs text-base-content/60">同理心</span>
            </span>
            <span class="flex flex-col items-center">
              <span class="text-2xl font-semibold tabular-nums">{@evaluation.communication_score}</span>
              <span class="text-xs text-base-content/60">沟通</span>
            </span>
          </div>
          <p class="mt-2 text-center text-sm font-medium">
            总分 {Decimal.to_string(@evaluation.total_score, :normal)} · {grade_label(@evaluation.grade)}
          </p>
        </div>
        """

      _ ->
        assigns = %{
          evaluation_status: session.evaluation_status,
          evaluation_error: session.evaluation_error
        }

        ~H"""
        <p :if={@evaluation_status == :failed} class="alert alert-warning alert-soft text-xs">
          评分失败：{@evaluation_error || "请稍后重试"}
        </p>
        """
    end
  end

  # ── helpers ───────────────────────────────────────────────

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

  defp session_status_text(:active), do: "进行中"
  defp session_status_text(:completed), do: "已完成"
  defp session_status_text(:abandoned), do: "已放弃"
  defp session_status_text(_), do: "—"

  defp assignment_status_text(:assigned), do: "已分配"
  defp assignment_status_text(:in_progress), do: "进行中"
  defp assignment_status_text(:completed), do: "已完成"
  defp assignment_status_text(:expired), do: "已过期"
  defp assignment_status_text(_), do: "—"

  defp grade_label(:excellent), do: "优秀"
  defp grade_label(:good), do: "良好"
  defp grade_label(:pass), do: "及格"
  defp grade_label(:borderline), do: "边缘"
  defp grade_label(:fail), do: "不及格"
  defp grade_label(_), do: "—"

  defp format_date(nil), do: "—"

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%m-%d %H:%M")
  end

  defp format_date(_), do: "—"

  # 列表里的 assignment 已 preload :patient，因此可以拿到病人姓名 / 情境 / 主诉。
  defp patient_name_for(%{patient: %Patient{name: name}}), do: name || "未命名病人"
  defp patient_name_for(_), do: "已分配的病人"

  defp patient_scenario_title(%{patient: %Patient{scenario_title: title}}), do: title
  defp patient_scenario_title(_), do: nil

  defp patient_complaint(%{patient: %Patient{complaint: complaint}}), do: complaint
  defp patient_complaint(_), do: nil
end
