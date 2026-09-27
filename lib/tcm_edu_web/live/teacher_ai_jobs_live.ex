defmodule TcmEduWeb.TeacherAIJobsLive do
  @moduledoc """
  AI 任务管理 at `/teacher/ai/jobs`.

  展示当前租户的 AI 出题任务（`TcmEdu.Quiz.QuizJob`）与关联 Oban job 的
  执行状态，支持按状态筛选、只看我的、失败重试与记录删除。

  列表通过 PubSub（`quiz_jobs:<tenant>`）实时刷新；Oban 侧的 state
  （available / executing / completed / discarded …）每次加载时从
  `oban_jobs` 表批量查询，作为业务状态之外的执行层参考。
  """

  use TcmEduWeb, :live_view

  import Ecto.Query, only: [from: 2]
  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.Quiz.{QuestionBank, QuizJob}
  alias TcmEdu.Workers.QuizGenerationWorker

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @statuses ~w(all pending running completed failed)
  @page_limit 50

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher

    if connected?(socket) do
      Phoenix.PubSub.subscribe(TcmEdu.PubSub, QuizGenerationWorker.topic(teacher.tenant))
    end

    {:ok,
     socket
     |> assign(:page_title, "AI 任务管理")
     |> assign(:status_filter, "all")
     |> assign(:mine_only, true)
     |> assign(:confirming, nil)
     |> load_banks()
     |> load_jobs()}
  end

  @impl true
  def handle_event("filter-status", %{"filter" => %{"status" => status}}, socket) do
    status = if status in @statuses, do: status, else: "all"
    {:noreply, socket |> assign(:status_filter, status) |> load_jobs()}
  end

  def handle_event("toggle-mine", %{"filter" => params}, socket) do
    {:noreply,
     socket |> assign(:mine_only, Map.get(params, "mine_only") == "true") |> load_jobs()}
  end

  def handle_event("retry", %{"id" => id}, socket) do
    teacher = socket.assigns.current_teacher

    case find_job(socket, id) do
      %QuizJob{status: :failed} = job ->
        {:noreply, retry_job(socket, job, teacher)}

      _ ->
        {:noreply, put_flash(socket, :error, "任务不存在或当前状态无需重试")}
    end
  end

  def handle_event("ask-delete", %{"id" => id}, socket) do
    case find_job(socket, id) do
      nil -> {:noreply, put_flash(socket, :error, "任务不存在")}
      job -> {:noreply, assign(socket, :confirming, job)}
    end
  end

  def handle_event("cancel-delete", _params, socket) do
    {:noreply, assign(socket, :confirming, nil)}
  end

  def handle_event("delete", _params, socket) do
    teacher = socket.assigns.current_teacher

    case socket.assigns.confirming do
      nil ->
        {:noreply, socket}

      job ->
        case Ash.destroy(job, actor: teacher.actor, tenant: teacher.tenant) do
          :ok ->
            {:noreply,
             socket
             |> assign(:confirming, nil)
             |> load_jobs()
             |> put_flash(:info, "任务记录已删除")}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, "删除失败：#{ash_message(error)}")}
        end
    end
  end

  @impl true
  def handle_info({:quiz_job_event, :task_completed, payload}, socket) do
    teacher = socket.assigns.current_teacher
    socket = load_jobs(socket)

    if payload.requested_by_id == teacher.id do
      {:noreply,
       put_flash(
         socket,
         :info,
         "AI 出题完成：《#{payload.topic}》已生成 #{payload.generated_count} 道习题"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:quiz_job_event, :task_failed, payload}, socket) do
    teacher = socket.assigns.current_teacher
    socket = load_jobs(socket)

    if payload.requested_by_id == teacher.id do
      {:noreply,
       put_flash(socket, :error, "AI 出题失败：《#{payload.topic}》#{payload.error_message || ""}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:quiz_job_event, _type, _payload}, socket) do
    {:noreply, load_jobs(socket)}
  end

  # ── actions ────────────────────────────────────────────────

  defp retry_job(socket, %QuizJob{} = job, teacher) do
    with {:ok, reset} <-
           job
           |> Ash.Changeset.for_update(:retry, %{oban_job_id: nil},
             actor: teacher.actor,
             tenant: teacher.tenant
           )
           |> Ash.update(),
         {:ok, oban_job} <-
           QuizGenerationWorker.new(%{"tenant" => teacher.tenant, "quiz_job_id" => job.id})
           |> Oban.insert(),
         {:ok, _} <- maybe_record_oban_id(reset, oban_job, teacher) do
      socket
      |> assign(:confirming, nil)
      |> load_jobs()
      |> put_flash(:info, "已重新提交《#{job.topic}》")
    else
      {:error, error} -> put_flash(socket, :error, "重试失败：#{ash_message(error)}")
    end
  end

  defp maybe_record_oban_id(_job, %{id: nil}, _teacher), do: {:ok, :skipped}

  defp maybe_record_oban_id(job, %{id: oban_id}, teacher) do
    job
    |> Ash.Changeset.for_update(:set_oban_job, %{oban_job_id: oban_id},
      actor: teacher.actor,
      tenant: teacher.tenant
    )
    |> Ash.update()
  end

  # ── loading ────────────────────────────────────────────────

  defp load_banks(socket) do
    teacher = socket.assigns.current_teacher

    banks =
      try do
        QuestionBank
        |> Ash.Query.for_read(:read, %{}, actor: teacher.actor, tenant: teacher.tenant)
        |> Ash.read!()
        |> Map.new(&{&1.id, &1.name})
      rescue
        _ -> %{}
      end

    assign(socket, :bank_names, banks)
  end

  defp load_jobs(socket) do
    teacher = socket.assigns.current_teacher
    filter = socket.assigns.status_filter
    mine_only = socket.assigns.mine_only

    jobs =
      try do
        query =
          QuizJob
          |> Ash.Query.for_read(:read, %{}, actor: teacher.actor, tenant: teacher.tenant)
          |> Ash.Query.sort(inserted_at: :desc)
          |> Ash.Query.limit(@page_limit)

        query =
          if filter in ["pending", "running", "completed", "failed"] do
            status = String.to_existing_atom(filter)
            Ash.Query.filter(query, status == ^status)
          else
            query
          end

        query =
          if mine_only do
            teacher_id = teacher.id
            Ash.Query.filter(query, requested_by_id == ^teacher_id)
          else
            query
          end

        Ash.read!(query)
      rescue
        _ -> []
      end

    socket
    |> assign(:jobs, jobs)
    |> assign(:oban_states, oban_states(Enum.map(jobs, & &1.oban_job_id)))
  end

  # 批量查询 Oban 执行层状态；查不到（如测试 manual 模式）则返回空 map，
  # 页面回退显示"—"，不影响业务状态展示。
  defp oban_states(ids) do
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      %{}
    else
      TcmEdu.Repo.all(from(j in Oban.Job, where: j.id in ^ids, select: {j.id, j.state}))
      |> Map.new()
    end
  rescue
    _ -> %{}
  end

  defp find_job(socket, id) do
    Enum.find(socket.assigns.jobs, &(&1.id == id))
  end

  # ── display helpers ────────────────────────────────────────

  defp status_badge(:pending), do: "badge-info"
  defp status_badge(:running), do: "badge-warning"
  defp status_badge(:completed), do: "badge-success"
  defp status_badge(:failed), do: "badge-error"
  defp status_badge(_), do: "badge-ghost"

  defp status_text(:pending), do: "排队中"
  defp status_text(:running), do: "生成中"
  defp status_text(:completed), do: "已完成"
  defp status_text(:failed), do: "失败"
  defp status_text(_), do: "未知"

  defp oban_state_text(%{oban_job_id: nil}, _states), do: "—"
  defp oban_state_text(%{oban_job_id: id}, states), do: Map.get(states, id, "—")

  defp type_label("single"), do: "单选"
  defp type_label("multi"), do: "多选"
  defp type_label("judge"), do: "判断"
  defp type_label("essay"), do: "简答"
  defp type_label(other), do: to_string(other)

  defp status_options,
    do: [
      {"全部", "all"},
      {"排队中", "pending"},
      {"生成中", "running"},
      {"已完成", "completed"},
      {"失败", "failed"}
    ]

  defp format_time(nil), do: "-"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M")

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
