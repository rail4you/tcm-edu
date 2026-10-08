defmodule TcmEduWeb.TeacherAIImageLive do
  @moduledoc """
  AI medical illustration at `/teacher/ai/image`.

  教师填写画面描述后，LiveView 创建 `TcmEdu.AI.GenerationJob`
  （`kind: :image`）并向 Oban 插入 `TcmEdu.Workers.AiGenerationWorker`，
  生成（文生图 + 轮询 + OSS 归档）在后台完成。结果落库，离开页面再返回
  仍可看到进度/图片；Worker 向 `ai_jobs:<tenant>` 广播状态，本页订阅刷新。
  每张图可直接设为某门课程的封面。
  """

  use TcmEduWeb, :live_view

  import TcmEduWeb.TeacherComponents, only: [teacher_shell: 1]

  require Ash.Query

  alias TcmEdu.AI.GenerationJob
  alias TcmEdu.Courses.Course
  alias TcmEdu.Workers.AiGenerationWorker
  alias TcmEduWeb.CourseCover

  on_mount {TcmEduWeb.TeacherAuth, :ensure_teacher}

  @impl true
  def mount(_params, _session, socket) do
    teacher = socket.assigns.current_teacher

    if connected?(socket) do
      Phoenix.PubSub.subscribe(TcmEdu.PubSub, AiGenerationWorker.topic(teacher.tenant))
    end

    {:ok,
     socket
     |> assign(:page_title, "AI 配图")
     |> assign(:page_subtitle, "生成经络腧穴、中药、示意图等教学配图，自动归档")
     |> assign(:form, image_form(%{}))
     |> assign(:courses, list_courses(teacher))
     |> assign(:cover_course_id, nil)
     |> load_latest()}
  end

  @impl true
  def handle_event("validate", %{"image" => params}, socket) do
    {:noreply, assign(socket, :form, image_form(params))}
  end

  def handle_event("generate", %{"image" => params}, socket) do
    changeset = image_changeset(params)

    cond do
      not changeset.valid? ->
        {:noreply, assign(socket, :form, Phoenix.Component.to_form(changeset, as: "image"))}

      socket.assigns.generating ->
        {:noreply, socket}

      true ->
        {:noreply, submit_job(socket, changeset)}
    end
  end

  def handle_event("select-cover-course", %{"cover" => %{"course_id" => course_id}}, socket) do
    {:noreply, assign(socket, :cover_course_id, empty_to_nil(course_id))}
  end

  def handle_event("set-cover", %{"url" => url}, socket) do
    teacher = socket.assigns.current_teacher

    with course_id when not is_nil(course_id) <- socket.assigns.cover_course_id,
         {:ok, course} <- fetch_course(course_id, teacher),
         :ok <- CourseCover.attach_from_url(course, teacher, url, basename(url)) do
      {:noreply, put_flash(socket, :info, "已设为《#{course.title}》的封面")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "请先选择一门课程")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "课程不存在或无权限")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, "设为封面失败：#{message}")}
    end
  end

  @impl true
  def handle_info({:ai_job_event, _type, %{kind: :image} = payload}, socket) do
    teacher = socket.assigns.current_teacher

    if payload.requested_by_id == teacher.id do
      socket = load_latest(socket)

      case payload.status do
        :completed -> {:noreply, put_flash(socket, :info, "配图已生成并归档")}
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
    prompt = get.(:prompt) |> to_string() |> String.trim()

    params = %{
      "prompt" => prompt,
      "style" => empty_to_nil(get.(:style)),
      "size" => empty_to_nil(get.(:size))
    }

    with {:ok, job} <-
           GenerationJob.request_generation_job(
             %{
               kind: :image,
               title: title_from(prompt),
               params: params,
               requested_by_id: teacher.id,
               requested_by_email: teacher.email
             },
             actor: teacher.actor,
             tenant: teacher.tenant
           ),
         {:ok, _oban_job} <- enqueue(job, teacher) do
      socket
      |> assign(:form, image_form(%{}))
      |> assign(:job, %{job | status: :pending, progress: 0})
      |> assign(:generating, true)
      |> assign(:urls, [])
      |> put_flash(:info, "已提交后台生成，可离开页面，完成后有提示")
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
        |> Ash.Query.for_read(:latest_mine, %{requested_by_id: teacher.id, kind: :image},
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
    |> assign(:urls, [])
  end

  defp apply_job(socket, %GenerationJob{} = job) do
    urls = if job.status == :completed, do: (job.result || %{})["urls"] || [], else: []

    socket
    |> assign(:job, job)
    |> assign(:generating, job.status in [:pending, :running])
    |> assign(:urls, urls)
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

  defp title_from(prompt) do
    if String.length(prompt) > 40, do: String.slice(prompt, 0, 40) <> "…", else: prompt
  end

  defp style_options,
    do: [{"写实", "realistic"}, {"水墨", "ink"}, {"扁平插画", "flat"}, {"解剖图", "anatomy"}]

  defp list_courses(teacher) do
    case Course
         |> Ash.Query.for_read(:list_by_teacher, %{teacher_id: teacher.id},
           actor: teacher.actor,
           tenant: teacher.tenant
         )
         |> Ash.read() do
      {:ok, courses} -> Enum.sort_by(courses, & &1.title)
      _ -> []
    end
  end

  defp fetch_course(course_id, teacher) do
    case Ash.get(Course, course_id, actor: teacher.actor, tenant: teacher.tenant) do
      {:ok, course} when not is_nil(course) -> {:ok, course}
      _ -> {:error, :not_found}
    end
  end

  defp basename(url) do
    case URI.parse(url) do
      %URI{path: path} when is_binary(path) ->
        path |> Path.basename() |> then(fn b -> if b == "", do: "ai-cover.png", else: b end)

      _ ->
        "ai-cover.png"
    end
  end

  defp size_options, do: [{"方形 1024", "1024x1024"}, {"横版 16:9", "16:9"}, {"竖版 9:16", "9:16"}]

  defp image_form(params) do
    params |> image_changeset() |> Phoenix.Component.to_form(as: "image")
  end

  defp image_changeset(params) do
    types = %{prompt: :string, style: :string, size: :string}

    {%{style: "realistic", size: "1024x1024"}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:prompt])
    |> Ecto.Changeset.validate_length(:prompt, max: 500)
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
