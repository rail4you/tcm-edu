defmodule TcmEduWeb.TeacherAIQuizLive do
  @moduledoc """
  AI 出题 at `/teacher/ai/quiz`.

  教师选择目标题库并填写主题 / 题型 / 难度后提交，LiveView 只做两件事：

    1. 创建 `TcmEdu.Quiz.QuizJob`（状态 `:pending`）；
    2. 向 Oban 插入 `TcmEdu.Workers.QuizGenerationWorker` 任务后立即返回。

  真正的生成（Jido agent + 结构化验证 + 题目入库）发生在 Oban worker 里，
  与 LiveView 进程无关——提交后可以直接离开页面，生成不会中断。

  Worker 每次状态变迁都向 `quiz_jobs:<tenant>` 广播，本页面订阅后：

    * 刷新「我的生成任务」列表；
    * 生成成功时在页面顶部展示成功 banner（含跳转题库按钮）并 flash 提示。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.Quiz.{QuestionBank, QuizJob}
  alias TcmEdu.Workers.QuizGenerationWorker

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @types ~w(single multi judge essay)
  @recent_limit 10
  # 进入页面时，只把最近 24 小时内完成的任务当 banner 展示，避免陈旧打扰
  @banner_window_hours 24

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher

    if connected?(socket) do
      Phoenix.PubSub.subscribe(TcmEdu.PubSub, QuizGenerationWorker.topic(teacher.tenant))
    end

    {:ok,
     socket
     |> assign(:page_title, "AI 出题")
     |> assign(:page_subtitle, "Jido agent 后台生成，可离开页面；完成后有横幅提示")
     |> assign(:form, quiz_form(%{}))
     |> assign(:submitting, false)
     |> load_banks()
     |> load_jobs()
     |> load_banner()}
  end

  @impl true
  def handle_event("validate", %{"quiz" => params}, socket) do
    {:noreply, assign(socket, :form, quiz_form(params))}
  end

  def handle_event("submit", %{"quiz" => params}, socket) do
    changeset = quiz_changeset(params)

    cond do
      not changeset.valid? ->
        {:noreply, assign(socket, :form, Phoenix.Component.to_form(changeset, as: "quiz"))}

      socket.assigns.submitting ->
        {:noreply, socket}

      true ->
        submit_job(socket, changeset)
    end
  end

  def handle_event("dismiss-banner", _params, socket) do
    dismissed_id = socket.assigns[:banner_job] && socket.assigns.banner_job.id

    {:noreply,
     socket
     |> assign(:banner_job, nil)
     |> assign(:banner_dismissed_id, dismissed_id)}
  end

  def handle_event("retry", %{"id" => id}, socket) do
    teacher = socket.assigns.current_teacher

    case find_my_job(socket, id) do
      %QuizJob{status: :failed} = job ->
        {:noreply, retry_job(socket, job, teacher)}

      _ ->
        {:noreply, put_flash(socket, :error, "任务不存在或当前状态无需重试")}
    end
  end

  @impl true
  def handle_info({:quiz_job_event, :task_completed, payload}, socket) do
    teacher = socket.assigns.current_teacher

    if payload.requested_by_id == teacher.id do
      socket =
        socket
        |> load_jobs()
        |> load_banner()

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

    if payload.requested_by_id == teacher.id do
      {:noreply,
       socket
       |> load_jobs()
       |> put_flash(:error, "AI 出题失败：《#{payload.topic}》#{payload.error_message || ""}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:quiz_job_event, _type, _payload}, socket) do
    {:noreply, load_jobs(socket)}
  end

  # ── submit ─────────────────────────────────────────────────

  defp submit_job(socket, changeset) do
    teacher = socket.assigns.current_teacher
    get = &Ecto.Changeset.get_field(changeset, &1)
    socket = assign(socket, :submitting, true)

    with {:bank, %QuestionBank{} = bank} <- {:bank, find_bank(socket, get.(:bank_id))},
         {:ok, job} <- request_job(teacher, bank, get),
         {:ok, _oban_job} <- enqueue(job, teacher) do
      {:noreply,
       socket
       |> assign(:submitting, false)
       |> assign(:form, quiz_form(%{"bank_id" => bank.id}))
       |> load_jobs()
       |> put_flash(:info, "已提交后台生成《#{job.topic}》，可离开页面，完成时会有横幅提示")}
    else
      {:bank, nil} ->
        {:noreply,
         socket
         |> assign(:submitting, false)
         |> put_flash(:error, "请先选择目标题库")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:submitting, false)
         |> put_flash(:error, "提交失败：#{ash_message(error)}")}
    end
  end

  defp request_job(teacher, bank, get) do
    QuizJob.request_quiz_job(
      %{
        bank_id: bank.id,
        topic: get.(:topic) |> to_string() |> String.trim(),
        subject: empty_to_nil(get.(:subject)) || "中医",
        question_count: get.(:question_count) || 5,
        question_types: get.(:question_types) || ["single"],
        difficulty: get.(:difficulty) || 3,
        knowledge_points: split_points(get.(:knowledge_points)),
        requirements: empty_to_nil(get.(:requirements)),
        requested_by_id: teacher.id,
        requested_by_email: teacher.email
      },
      actor: teacher.actor,
      tenant: teacher.tenant
    )
  end

  defp enqueue(%QuizJob{} = job, teacher) do
    args = %{"tenant" => teacher.tenant, "quiz_job_id" => job.id}

    with {:ok, oban_job} <- QuizGenerationWorker.new(args) |> Oban.insert(),
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

  defp retry_job(socket, %QuizJob{} = job, teacher) do
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
      |> put_flash(:info, "已重新提交《#{job.topic}》")
    else
      {:error, error} -> put_flash(socket, :error, "重试失败：#{ash_message(error)}")
    end
  end

  # ── loading ────────────────────────────────────────────────

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
        QuizJob
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
        QuizJob
        |> Ash.Query.for_read(:recent_completed, %{requested_by_id: teacher.id},
          actor: teacher.actor,
          tenant: teacher.tenant
        )
        |> Ash.Query.limit(1)
        |> Ash.read_one!()
        |> case do
          %QuizJob{completed_at: %DateTime{} = done} = job ->
            if DateTime.compare(done, cutoff) == :gt, do: job, else: nil

          _ ->
            nil
        end
      rescue
        _ -> nil
      end

    # 用户手动关闭后，同一任务不再弹回；新完成的任务仍会展示
    if banner && banner.id == socket.assigns[:banner_dismissed_id] do
      assign(socket, :banner_job, nil)
    else
      assign(socket, :banner_job, banner)
    end
  end

  defp find_bank(socket, bank_id) do
    Enum.find(socket.assigns.banks, &(&1.id == bank_id))
  end

  defp find_my_job(socket, id) do
    Enum.find(socket.assigns.jobs, &(&1.id == id))
  end

  # ── form ───────────────────────────────────────────────────

  defp quiz_form(params) do
    params |> quiz_changeset() |> Phoenix.Component.to_form(as: "quiz")
  end

  defp quiz_changeset(params) do
    {%{subject: "中医", question_count: 5, difficulty: 3, question_types: ["single"]},
     %{
       bank_id: :string,
       topic: :string,
       subject: :string,
       question_count: :integer,
       question_types: {:array, :string},
       difficulty: :integer,
       knowledge_points: :string,
       requirements: :string
     }}
    |> Ecto.Changeset.cast(params, [
      :bank_id,
      :topic,
      :subject,
      :question_count,
      :question_types,
      :difficulty,
      :knowledge_points,
      :requirements
    ])
    |> Ecto.Changeset.validate_required([:bank_id, :topic])
    |> Ecto.Changeset.validate_length(:topic, min: 2, max: 200)
    |> Ecto.Changeset.validate_number(:question_count,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 10
    )
    |> Ecto.Changeset.validate_number(:difficulty,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 5
    )
    |> validate_types()
  end

  defp validate_types(changeset) do
    case Ecto.Changeset.get_field(changeset, :question_types) do
      types when is_list(types) and types != [] ->
        if Enum.all?(types, &(&1 in @types)) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :question_types, "题型选择非法")
        end

      _ ->
        Ecto.Changeset.add_error(changeset, :question_types, "请至少选择一种题型")
    end
  end

  defp split_points(nil), do: []
  defp split_points(""), do: []

  defp split_points(text) when is_binary(text) do
    text |> String.split(~r/[,，、]/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp split_points(_), do: []

  # ── display helpers ────────────────────────────────────────

  defp type_label("single"), do: "单选"
  defp type_label("multi"), do: "多选"
  defp type_label("judge"), do: "判断"
  defp type_label("essay"), do: "简答"
  defp type_label(other), do: to_string(other)

  defp type_options, do: [{"单选", "single"}, {"多选", "multi"}, {"判断", "judge"}, {"简答", "essay"}]

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

  defp bank_name(banks, bank_id) do
    case Enum.find(banks, &(&1.id == bank_id)) do
      nil -> "—"
      bank -> bank.name
    end
  end

  defp format_time(nil), do: "-"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%m-%d %H:%M")

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value) when is_binary(value), do: String.trim(value)
  defp empty_to_nil(value), do: value

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
