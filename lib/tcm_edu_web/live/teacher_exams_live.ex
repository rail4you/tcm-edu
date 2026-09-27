defmodule TcmEduWeb.TeacherExamsLive do
  @moduledoc """
  考试管理 at `/teacher/exams`.

  试卷列表（含摘要指标）、新建试卷、AI 智能组卷、发布/关闭/删除。
  AI 组卷是后台任务（`TcmEdu.Exam.ExamJob` + Oban），提交后由
  `TcmEdu.Workers.ExamGenerationWorker` 完成，页面订阅 PubSub 实时刷新。

  两个表单均走 `AshPhoenix.Form`:
    * `exam_form` → `for_create(Exam, :create, ...)`,`relate_actor(:created_by)`
      由 resource 的 change 块基于 `actor:` 自动绑定;
    * `ai_form` → `for_create(ExamJob, :request, ...)`,`requested_by_id` /
      `requested_by_email` 由 `prepare_source` 注入。
  发布/关闭/删除/重试都是单步 action 调用,保持 `Ash.Changeset` 直调。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.Exam.{Exam, ExamJob}
  alias TcmEdu.Quiz.QuestionBank
  alias TcmEdu.Workers.ExamGenerationWorker

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @recent_limit 8
  @banner_window_hours 24

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher

    if connected?(socket) do
      Phoenix.PubSub.subscribe(TcmEdu.PubSub, ExamGenerationWorker.topic(teacher.tenant))
    end

    {:ok,
     socket
     |> assign(:page_title, "考试管理")
     |> assign(:page_subtitle, "组卷、发布、分配与批改")
     |> assign(:create_modal, false)
     |> assign(:create_form, exam_form(teacher, %{}))
     |> assign(:ai_modal, false)
     |> assign(:ai_form, ai_form(teacher, %{}))
     |> assign(:ai_submitting, false)
     |> assign(:deleting, nil)
     |> assign(:banner_job, nil)
     |> assign(:banner_dismissed_id, nil)
     |> load_exams()
     |> load_banks()
     |> load_jobs()
     |> load_banner()}
  end

  # ── 新建试卷 ──────────────────────────────────────────────

  @impl true
  def handle_event("open-create", _params, socket) do
    {:noreply,
     assign(socket,
       create_modal: true,
       create_form: exam_form(socket.assigns.current_teacher, %{})
     )}
  end

  def handle_event("close-create", _params, socket) do
    {:noreply, assign(socket, :create_modal, false)}
  end

  def handle_event("validate-create", %{"exam" => params}, socket) do
    {:noreply,
     assign(socket, :create_form, AshPhoenix.Form.validate(socket.assigns.create_form, params))}
  end

  def handle_event("create-exam", %{"exam" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.create_form, params)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, exam} ->
        {:noreply,
         socket
         |> assign(:create_modal, false)
         |> put_flash(:info, "试卷《#{exam.name}》已创建，去添加题目吧")
         |> push_navigate(to: "/teacher/exams/#{exam.id}/build")}

      {:error, form} ->
        {:noreply, assign(socket, :create_form, form)}
    end
  end

  # ── 发布 / 关闭 / 删除 ────────────────────────────────────

  def handle_event("publish", %{"id" => id}, socket) do
    teacher = socket.assigns.current_teacher

    case find_exam(socket, id) do
      %Exam{} = exam ->
        case exam
             |> Ash.Changeset.for_update(:publish, %{},
               actor: teacher.actor,
               tenant: teacher.tenant
             )
             |> Ash.update() do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "试卷已发布，可分配给学生")
             |> load_exams()}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, ash_message(error))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "试卷不存在")}
    end
  end

  def handle_event("close", %{"id" => id}, socket) do
    teacher = socket.assigns.current_teacher

    case find_exam(socket, id) do
      %Exam{} = exam ->
        case exam
             |> Ash.Changeset.for_update(:close, %{},
               actor: teacher.actor,
               tenant: teacher.tenant
             )
             |> Ash.update() do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "试卷已关闭，不能再分配")
             |> load_exams()}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, ash_message(error))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "试卷不存在")}
    end
  end

  def handle_event("confirm-delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :deleting, find_exam(socket, id))}
  end

  def handle_event("close-delete", _params, socket) do
    {:noreply, assign(socket, :deleting, nil)}
  end

  def handle_event("delete", _params, socket) do
    teacher = socket.assigns.current_teacher
    exam = socket.assigns.deleting

    case Ash.destroy(exam, actor: teacher.actor, tenant: teacher.tenant) do
      :ok ->
        {:noreply,
         socket
         |> assign(:deleting, nil)
         |> put_flash(:info, "试卷已删除")
         |> load_exams()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  # ── AI 智能组卷 ───────────────────────────────────────────

  def handle_event("open-ai", _params, socket) do
    if socket.assigns.banks == [] do
      {:noreply, put_flash(socket, :error, "请先在「题库管理」创建题库并添加习题")}
    else
      {:noreply,
       assign(socket,
         ai_modal: true,
         ai_submitting: false,
         ai_form:
           ai_form(socket.assigns.current_teacher, %{
             "bank_id" => hd(socket.assigns.banks).id
           })
       )}
    end
  end

  def handle_event("close-ai", _params, socket) do
    {:noreply, assign(socket, ai_modal: false, ai_submitting: false)}
  end

  def handle_event("validate-ai", %{"exam" => params}, socket) do
    {:noreply, assign(socket, :ai_form, AshPhoenix.Form.validate(socket.assigns.ai_form, params))}
  end

  def handle_event("submit-ai", %{"exam" => params}, socket) do
    teacher = socket.assigns.current_teacher
    form = AshPhoenix.Form.validate(socket.assigns.ai_form, params)

    cond do
      not form.valid? ->
        {:noreply, assign(socket, :ai_form, form)}

      socket.assigns.ai_submitting ->
        {:noreply, socket}

      true ->
        submit_ai_job(socket, form, teacher)
    end
  end

  def handle_event("retry-ai", %{"id" => id}, socket) do
    teacher = socket.assigns.current_teacher

    case find_job(socket, id) do
      %ExamJob{status: :failed} = job ->
        {:noreply, retry_job(socket, job, teacher)}

      _ ->
        {:noreply, put_flash(socket, :error, "任务不存在或无需重试")}
    end
  end

  def handle_event("dismiss-banner", _params, socket) do
    dismissed_id = socket.assigns[:banner_job] && socket.assigns.banner_job.id

    {:noreply,
     socket
     |> assign(:banner_job, nil)
     |> assign(:banner_dismissed_id, dismissed_id)}
  end

  # ── PubSub ────────────────────────────────────────────────

  @impl true
  def handle_info({:exam_job_event, :task_completed, payload}, socket) do
    teacher = socket.assigns.current_teacher

    if payload.requested_by_id == teacher.id do
      {:noreply,
       socket
       |> load_jobs()
       |> load_banner()
       |> put_flash(:info, "AI 组卷完成：《#{payload.name}》已生成，可在列表中发布")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:exam_job_event, :task_failed, payload}, socket) do
    teacher = socket.assigns.current_teacher

    if payload.requested_by_id == teacher.id do
      {:noreply,
       socket
       |> load_jobs()
       |> put_flash(:error, "AI 组卷失败：《#{payload.name}》#{payload.error_message || ""}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:exam_job_event, _type, _payload}, socket) do
    {:noreply, load_jobs(socket)}
  end

  # ── AI 提交 ───────────────────────────────────────────────

  defp submit_ai_job(socket, form, teacher) do
    case AshPhoenix.Form.submit(form, params: AshPhoenix.Form.params(form)) do
      {:ok, job} ->
        case enqueue(job, teacher) do
          {:ok, _oban_job} ->
            {:noreply,
             socket
             |> assign(:ai_modal, false)
             |> assign(:ai_submitting, false)
             |> load_jobs()
             |> put_flash(:info, "已提交后台组卷《#{job.name}》，完成后会在此页提示")}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:ai_submitting, false)
             |> put_flash(:error, "提交失败：#{ash_message(reason)}")}
        end

      {:error, form} ->
        {:noreply, assign(socket, :ai_form, form)}
    end
  end

  defp enqueue(%ExamJob{} = job, teacher) do
    args = %{"tenant" => teacher.tenant, "exam_job_id" => job.id}

    with {:ok, oban_job} <- ExamGenerationWorker.new(args) |> Oban.insert(),
         {:ok, _} <- maybe_record_oban_id(job, oban_job, teacher) do
      {:ok, oban_job}
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

  defp retry_job(socket, %ExamJob{} = job, teacher) do
    with {:ok, reset} <-
           job
           |> Ash.Changeset.for_update(:retry, %{oban_job_id: nil},
             actor: teacher.actor,
             tenant: teacher.tenant
           )
           |> Ash.update(),
         {:ok, _oban_job} <- enqueue(reset, teacher) do
      socket
      |> load_jobs()
      |> put_flash(:info, "已重新提交《#{job.name}》")
    else
      {:error, error} -> put_flash(socket, :error, "重试失败：#{ash_message(error)}")
    end
  end

  # ── loading ───────────────────────────────────────────────

  defp load_exams(socket) do
    teacher = socket.assigns.current_teacher

    exams =
      try do
        Exam
        |> Ash.Query.for_read(:read, %{}, actor: teacher.actor, tenant: teacher.tenant)
        |> Ash.Query.load([:total_questions, :total_score, :assigned_count])
        |> Ash.read!()
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      rescue
        _ -> []
      end

    assign(socket, :exams, exams)
  end

  defp load_banks(socket) do
    teacher = socket.assigns.current_teacher

    banks =
      try do
        QuestionBank
        |> Ash.Query.for_read(:read, %{}, actor: teacher.actor, tenant: teacher.tenant)
        |> Ash.read!()
        |> Enum.sort_by(& &1.name)
      rescue
        _ -> []
      end

    assign(socket, :banks, banks)
  end

  defp load_jobs(socket) do
    teacher = socket.assigns.current_teacher

    jobs =
      try do
        ExamJob
        |> Ash.Query.for_read(:list_mine, %{requested_by_id: teacher.id},
          actor: teacher.actor,
          tenant: teacher.tenant
        )
        |> Ash.Query.limit(@recent_limit)
        |> Ash.read!()
      rescue
        _ -> []
      end

    assign(socket, :jobs, jobs)
  end

  defp load_banner(socket) do
    teacher = socket.assigns.current_teacher
    cutoff = DateTime.add(DateTime.utc_now(), -@banner_window_hours * 3600, :second)

    banner =
      try do
        ExamJob
        |> Ash.Query.for_read(:recent_completed, %{requested_by_id: teacher.id},
          actor: teacher.actor,
          tenant: teacher.tenant
        )
        |> Ash.Query.limit(1)
        |> Ash.read_one!()
        |> case do
          %ExamJob{completed_at: %DateTime{} = done} = job ->
            if DateTime.compare(done, cutoff) == :gt, do: job, else: nil

          _ ->
            nil
        end
      rescue
        _ -> nil
      end

    if banner && banner.id == socket.assigns[:banner_dismissed_id] do
      assign(socket, :banner_job, nil)
    else
      assign(socket, :banner_job, banner)
    end
  end

  defp find_exam(socket, id) do
    Enum.find(socket.assigns.exams, &(&1.id == id))
  end

  defp find_job(socket, id) do
    Enum.find(socket.assigns.jobs, &(&1.id == id))
  end

  # ── forms ─────────────────────────────────────────────────

  # `:create` action 接受 name/subject/description/duration_minutes,`subject`
  # 由 attribute constraints (one_of: [...]) 自动校验,`duration_minutes`
  # 由 constraints (min: 5, max: 600) 自动校验。`created_by` 关系由 resource
  # 的 change(relate_actor(:created_by)) 在 actor 存在时自动绑定。
  defp exam_form(teacher, params) do
    Exam
    |> AshPhoenix.Form.for_create(:create,
      actor: teacher.actor,
      tenant: teacher.tenant,
      as: "exam",
      params: params
    )
    |> to_form()
  end

  # `:request` action 接受所有 AI 组卷字段(含 constraints 校验)。
  # `requested_by_id` / `requested_by_email` 由 `prepare_source` 服务端注入。
  defp ai_form(teacher, params) do
    ExamJob
    |> AshPhoenix.Form.for_create(:request,
      actor: teacher.actor,
      tenant: teacher.tenant,
      as: "exam",
      params: params,
      prepare_source: fn changeset ->
        changeset
        |> Ash.Changeset.force_change_attribute(:requested_by_id, teacher.id)
        |> Ash.Changeset.force_change_attribute(:requested_by_email, teacher.email)
      end
    )
    |> to_form()
  end

  # ── display helpers ───────────────────────────────────────

  defp subject_label(:traditional_chinese_medicine), do: "中医"
  defp subject_label(:western_medicine), do: "西医"
  defp subject_label(:anatomy), do: "解剖"
  defp subject_label(:physiology), do: "生理"
  defp subject_label(:pathology), do: "病理"
  defp subject_label(:pharmacology), do: "药理"
  defp subject_label(:clinical), do: "临床"
  defp subject_label(:nursing), do: "护理"
  defp subject_label(:public_health), do: "公卫"
  defp subject_label(:other), do: "其他"
  defp subject_label(other), do: to_string(other)

  defp subject_options,
    do: [
      {"中医", "traditional_chinese_medicine"},
      {"西医", "western_medicine"},
      {"解剖", "anatomy"},
      {"生理", "physiology"},
      {"病理", "pathology"},
      {"药理", "pharmacology"},
      {"临床", "clinical"},
      {"护理", "nursing"},
      {"公卫", "public_health"},
      {"其他", "other"}
    ]

  defp type_options, do: [{"单选", "single"}, {"多选", "multi"}, {"判断", "judge"}, {"简答", "essay"}]

  defp difficulty_options, do: Enum.map(1..5, &{to_string(&1), &1})

  defp duration_options, do: Enum.map([30, 45, 60, 90, 120], &{"#{&1} 分钟", &1})

  defp status_badge(:draft), do: "badge-ghost"
  defp status_badge(:published), do: "badge-success"
  defp status_badge(:closed), do: "badge-warning"
  defp status_badge(_), do: "badge-ghost"

  defp status_text(:draft), do: "草稿"
  defp status_text(:published), do: "已发布"
  defp status_text(:closed), do: "已关闭"
  defp status_text(_), do: "未知"

  defp job_status_badge(:pending), do: "badge-info"
  defp job_status_badge(:running), do: "badge-warning"
  defp job_status_badge(:completed), do: "badge-success"
  defp job_status_badge(:failed), do: "badge-error"
  defp job_status_badge(_), do: "badge-ghost"

  defp job_status_text(:pending), do: "排队中"
  defp job_status_text(:running), do: "组卷中"
  defp job_status_text(:completed), do: "已完成"
  defp job_status_text(:failed), do: "失败"
  defp job_status_text(_), do: "未知"

  defp bank_name(socket, bank_id) do
    case Enum.find(socket.assigns.banks, &(&1.id == bank_id)) do
      nil -> "—"
      bank -> bank.name
    end
  end

  defp format_time(nil), do: "-"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M")

  defp fmt_score(nil), do: "-"
  defp fmt_score(%Decimal{} = d), do: Decimal.to_string(d)
  defp fmt_score(n), do: to_string(n)

  defp metric(exams, status) when is_atom(status) do
    Enum.count(exams, &(&1.status == status))
  end

  defp assigned_count(exams), do: Enum.sum(Enum.map(exams, &(&1.assigned_count || 0)))

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
