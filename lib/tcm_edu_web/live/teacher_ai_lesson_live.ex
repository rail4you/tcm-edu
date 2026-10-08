defmodule TcmEduWeb.TeacherAILessonLive do
  @moduledoc """
  AI 备课 at `/teacher/ai/lesson-plan`.

  教师填写主题后，LiveView 只做两件事：

    1. 创建 `TcmEdu.AI.GenerationJob`（`kind: :lesson_plan`，状态 `:pending`）；
    2. 向 Oban 插入 `TcmEdu.Workers.AiGenerationWorker` 后立即返回。

  真正的生成发生在 Oban worker 里，与 LiveView 进程无关——提交后可以
  离开页面；结果落库后再次进入页面即可看到进度/教案。Worker 每次状态
  变迁向 `ai_jobs:<tenant>` 广播，本页订阅后刷新进度并展示结果。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.AI.GenerationJob
  alias TcmEdu.Courses.Course
  alias TcmEdu.Workers.AiGenerationWorker

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher

    if connected?(socket) do
      Phoenix.PubSub.subscribe(TcmEdu.PubSub, AiGenerationWorker.topic(teacher.tenant))
    end

    {:ok,
     socket
     |> assign(:page_title, "AI 备课")
     |> assign(:page_subtitle, "输入主题，AI 生成结构化教案，可一键存为课程草稿")
     |> assign(:form, plan_form(%{}))
     |> assign(:show_form, true)
     |> load_latest()}
  end

  @impl true
  def handle_event("validate", %{"plan" => params}, socket) do
    {:noreply, assign(socket, :form, plan_form(params))}
  end

  def handle_event("open-form", _params, socket) do
    {:noreply, assign(socket, :show_form, true)}
  end

  def handle_event("close-form", _params, socket) do
    {:noreply, assign(socket, :show_form, false)}
  end

  def handle_event("open-detail", _params, socket) do
    {:noreply, assign(socket, :detail, socket.assigns.plan_doc)}
  end

  def handle_event("close-detail", _params, socket) do
    {:noreply, assign(socket, :detail, nil)}
  end

  def handle_event("generate", %{"plan" => params}, socket) do
    changeset = plan_changeset(params)

    cond do
      not changeset.valid? ->
        {:noreply, assign(socket, :form, Phoenix.Component.to_form(changeset, as: "plan"))}

      socket.assigns.generating ->
        {:noreply, socket}

      true ->
        {:noreply, submit_job(socket, changeset)}
    end
  end

  def handle_event("save-draft", _params, socket) do
    teacher = socket.assigns.current_teacher
    topic = (socket.assigns.job && socket.assigns.job.title) || "AI 教案"

    attrs = %{
      title: String.slice(topic, 0, 100),
      subtitle: "AI 备课生成",
      description: socket.assigns.plan,
      level: :beginner,
      price_cents: 0,
      teacher_id: teacher.id
    }

    case Course.create_course(attrs, actor: teacher.actor, tenant: teacher.tenant) do
      {:ok, course} ->
        {:noreply,
         socket
         |> put_flash(:info, "已存为课程草稿《#{course.title}》")
         |> push_navigate(to: "/teacher/courses")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, ash_message(error))}
    end
  end

  @impl true
  def handle_info({:ai_job_event, _type, %{kind: :lesson_plan} = payload}, socket) do
    teacher = socket.assigns.current_teacher

    if payload.requested_by_id == teacher.id do
      socket = load_latest(socket)

      case payload.status do
        :completed -> {:noreply, put_flash(socket, :info, "教案已生成")}
        :failed -> {:noreply, put_flash(socket, :error, "生成失败：#{payload.error_message}")}
        _ -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:ai_job_event, _type, _payload}, socket), do: {:noreply, socket}

  # ── submit ─────────────────────────────────────────────────

  defp submit_job(socket, changeset) do
    teacher = socket.assigns.current_teacher
    get = &Ecto.Changeset.get_field(changeset, &1)
    topic = get.(:topic) |> String.trim()

    params = %{
      "subject" => empty_to_nil(get.(:subject)) || "中医",
      "level" => get.(:level) |> to_string(),
      "audience" => empty_to_nil(get.(:audience))
    }

    with {:ok, job} <-
           GenerationJob.request_generation_job(
             %{
               kind: :lesson_plan,
               title: topic,
               params: params,
               requested_by_id: teacher.id,
               requested_by_email: teacher.email
             },
             actor: teacher.actor,
             tenant: teacher.tenant
           ),
         {:ok, _oban_job} <- enqueue(job, teacher) do
      socket
      |> assign(:show_form, false)
      |> assign(:form, plan_form(%{}))
      |> assign(:job, %{job | status: :pending, progress: 0})
      |> assign(:generating, true)
      |> assign(:plan, nil)
      |> assign(:plan_doc, empty_doc())
      |> assign(:detail, nil)
      |> put_flash(:info, "已提交后台生成《#{topic}》，可离开页面，完成后有提示")
    else
      {:error, error} ->
        put_flash(socket, :error, "提交失败：#{ash_message(error)}")
    end
  end

  defp enqueue(%GenerationJob{} = job, teacher) do
    args = %{"tenant" => teacher.tenant, "generation_job_id" => job.id}

    with {:ok, oban_job} <- AiGenerationWorker.new(args) |> Oban.insert(),
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

  # ── loading ────────────────────────────────────────────────

  defp load_latest(socket) do
    teacher = socket.assigns.current_teacher

    job =
      try do
        GenerationJob
        |> Ash.Query.for_read(:latest_mine, %{requested_by_id: teacher.id, kind: :lesson_plan},
          actor: teacher.actor,
          tenant: teacher.tenant
        )
        |> Ash.read_one!()
      rescue
        _ -> nil
      end

    apply_job(socket, job)
  end

  defp apply_job(socket, nil) do
    socket
    |> assign(:job, nil)
    |> assign(:generating, false)
    |> assign(:plan, nil)
    |> assign(:plan_topic, nil)
    |> assign(:plan_doc, empty_doc())
    |> assign(:detail, nil)
    |> assign(:show_form, true)
  end

  defp apply_job(socket, %GenerationJob{} = job) do
    plan = if job.status == :completed, do: (job.result || %{})["plan"], else: nil

    socket
    |> assign(:job, job)
    |> assign(:generating, job.status in [:pending, :running])
    |> assign(:plan, plan)
    |> assign(:plan_topic, job.title)
    |> assign(:plan_doc, plan_doc(plan))
    |> assign(:detail, nil)
    |> assign(:show_form, false)
  end

  # ── display helpers ────────────────────────────────────────

  defp status_text(nil), do: "排队中"
  defp status_text(:pending), do: "排队中"
  defp status_text(:running), do: "生成中"
  defp status_text(:completed), do: "已完成"
  defp status_text(:failed), do: "失败"
  defp status_text(_), do: "未知"

  defp status_badge(:pending), do: "badge-info"
  defp status_badge(:running), do: "badge-warning"
  defp status_badge(:completed), do: "badge-success"
  defp status_badge(:failed), do: "badge-error"
  defp status_badge(_), do: "badge-ghost"

  defp progress_of(nil), do: 0
  defp progress_of(job), do: job.progress || 0

  defp level_options, do: [{"本科", "本科"}, {"规培", "规培"}, {"继续教育", "继续教育"}]

  # ── markdown 教案渲染 + 标题导航 ─────────────────────────────

  @heading_tags ~w(h1 h2 h3 h4 h5 h6)

  defp empty_doc, do: %{html: "", toc: []}

  # 把 markdown 教案转成带 id 锚点的 HTML，并按标题层级生成目录（TOC）。
  defp plan_doc(plan) when is_binary(plan) and plan != "" do
    nodes = plan |> markdown_to_html() |> Floki.parse_fragment!()
    {nodes, {toc, _seen}} = Floki.traverse_and_update(nodes, {[], %{}}, &heading_entry/2)

    %{html: Floki.raw_html(nodes), toc: toc}
  end

  defp plan_doc(_), do: empty_doc()

  defp markdown_to_html(text) do
    case Earmark.as_html(text) do
      {:ok, html, _} -> html
      {:error, html, _} -> html
    end
  end

  defp heading_entry({tag, attrs, children}, {toc, seen})
       when tag in @heading_tags do
    text = children |> Floki.text() |> String.trim()
    {id, seen} = unique_heading_id(slugify(text), seen)
    level = tag |> String.trim_leading("h") |> String.to_integer()
    entry = %{level: level, text: text, id: id}

    {{tag, [{"id", id} | attrs], children}, {toc ++ [entry], seen}}
  end

  defp heading_entry(node, acc), do: {node, acc}

  defp unique_heading_id("", seen), do: unique_heading_id("section", seen)

  defp unique_heading_id(base, seen) do
    case Map.get(seen, base) do
      nil -> {base, Map.put(seen, base, 1)}
      count -> {"#{base}-#{count + 1}", Map.put(seen, base, count + 1)}
    end
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
    |> String.trim("-")
  end

  defp audience_options, do: [{"大一", "大一"}, {"大二", "大二"}, {"大三", "大三"}, {"大四", "大四"}]

  defp plan_form(params) do
    params |> plan_changeset() |> Phoenix.Component.to_form(as: "plan")
  end

  defp plan_changeset(params) do
    types = %{topic: :string, subject: :string, level: :string, audience: :string}

    {%{level: "本科", audience: "大一"}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:topic])
    |> Ecto.Changeset.validate_length(:topic, max: 100)
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value) when is_binary(value), do: String.trim(value)

  defp ash_message(error) do
    Exception.message(error)
  rescue
    _ -> "操作失败，请稍后重试"
  end
end
