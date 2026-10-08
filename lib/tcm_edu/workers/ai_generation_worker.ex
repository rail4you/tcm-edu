defmodule TcmEdu.Workers.AiGenerationWorker do
  @moduledoc """
  Oban worker：执行一次 AI 生成任务（备课 / 配图）。

  流程：

    1. 按 `generation_job_id` + `tenant` 读 `TcmEdu.AI.GenerationJob`，
       置为 `:running`（progress 10）并广播；
    2. 按 `kind` 分派：
       * `:lesson_plan` → `TcmEdu.AI.LessonPlan.generate/1`，结果 `%{"plan" => md}`
       * `:image`       → `TcmEdu.AI.MedicalImage.generate_and_store/2`，结果 `%{"urls" => [...]}`
    3. 成功置 `:completed`（progress 100，写 `result`）；失败置 `:failed`
       （写 `error_message`），两种终态都广播并写站内通知。

  广播 topic：`"ai_jobs:<tenant>"`，消息
  `{:ai_job_event, :task_running | :task_completed | :task_failed, payload}`。
  payload 恒带 `requested_by_id` 与 `kind`，页面据此只展示自己的任务。

  Worker 与任何 LiveView 进程无关：教师提交后离开页面不影响生成，结果落库。

  ## 用法

      TcmEdu.Workers.AiGenerationWorker.new(%{
        "tenant" => "tenant_default",
        "generation_job_id" => job_id
      })
      |> Oban.insert()
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Ash.Query
  require Logger

  alias TcmEdu.AI.GenerationJob
  alias TcmEdu.AI.{LessonPlan, MedicalImage}
  alias TcmEdu.Notification.Notification

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"generation_job_id" => job_id} = args}) do
    tenant = args["tenant"] || "tenant_default"
    topic = topic(tenant)

    with {:ok, job} <- load_job(job_id, tenant),
         :ok <- ensure_pending(job),
         {:ok, running} <- mark(job, :mark_running, %{}, tenant),
         :ok <- broadcast(topic, :task_running, payload(running)) do
      run(running, tenant, topic)
    else
      {:skip, _} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def perform(%Oban.Job{args: args}) do
    {:error, "missing generation_job_id in args: #{inspect(args)}"}
  end

  # ── dispatch ───────────────────────────────────────────────

  defp run(%GenerationJob{kind: :lesson_plan} = job, tenant, topic) do
    params = job.params || %{}

    result =
      LessonPlan.generate(
        topic: job.title,
        subject: params["subject"] || "中医",
        level: params["level"] || "本科",
        audience: params["audience"]
      )

    case result do
      {:ok, plan} when is_binary(plan) and plan != "" ->
        complete(job, tenant, topic, %{"plan" => plan})

      {:ok, _} ->
        fail(job, tenant, topic, "AI 未返回教案内容，请调整主题后重试")

      {:error, reason} ->
        fail(job, tenant, topic, format_reason(reason))
    end
  rescue
    e -> fail(job, tenant, topic, Exception.message(e))
  end

  defp run(%GenerationJob{kind: :image} = job, tenant, topic) do
    params = job.params || %{}

    opts =
      [key_prefix: "ai/teacher", style: params["style"], size: params["size"]]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    prompt = params["prompt"] || job.title

    case MedicalImage.generate_and_store(prompt, opts) do
      {:ok, urls} when is_list(urls) and urls != [] ->
        complete(job, tenant, topic, %{"urls" => urls})

      {:ok, _} ->
        fail(job, tenant, topic, "AI 未返回可用图片，请调整描述后重试")

      {:error, reason} ->
        fail(job, tenant, topic, format_reason(reason))
    end
  rescue
    e -> fail(job, tenant, topic, Exception.message(e))
  end

  defp run(%GenerationJob{kind: kind} = job, tenant, topic) do
    fail(job, tenant, topic, "未知任务类型：#{inspect(kind)}")
  end

  # ── terminal states ────────────────────────────────────────

  defp complete(%GenerationJob{} = job, tenant, topic, result) do
    with {:ok, done} <- mark(job, :mark_completed, %{result: result}, tenant) do
      broadcast(topic, :task_completed, payload(done))
      notify(tenant, done)
      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp fail(%GenerationJob{} = job, tenant, topic, reason) do
    message = truncate(to_string(reason), 500)
    Logger.warning("[AiGenerationWorker] job=#{job.id} kind=#{job.kind} failed: #{message}")

    with {:ok, failed} <- mark(job, :mark_failed, %{error_message: message}, tenant) do
      broadcast(topic, :task_failed, payload(failed))
      notify(tenant, failed)
      :ok
    else
      _ -> :ok
    end
  end

  # ── loading ────────────────────────────────────────────────

  defp load_job(id, tenant) do
    case GenerationJob
         |> Ash.Query.filter(id == ^id)
         |> Ash.Query.limit(1)
         |> Ash.read_one(tenant: tenant, authorize?: false) do
      {:ok, %GenerationJob{} = job} -> {:ok, job}
      other -> {:error, "generation job not found: #{inspect(other)}"}
    end
  end

  defp ensure_pending(%GenerationJob{status: :completed}), do: {:skip, :already_done}
  defp ensure_pending(%GenerationJob{status: :failed}), do: {:skip, :failed_awaiting_retry}
  defp ensure_pending(%GenerationJob{}), do: :ok

  defp mark(%GenerationJob{} = job, action, params, tenant) do
    job
    |> Ash.Changeset.for_update(action, params)
    |> Ash.update(tenant: tenant, authorize?: false)
  end

  # ── notify + broadcast ─────────────────────────────────────

  defp notify(tenant, %GenerationJob{status: :completed} = job) do
    {title, body, route} = completed_copy(job)

    create_notification(tenant, job, title, body, route)
  end

  defp notify(tenant, %GenerationJob{status: :failed} = job) do
    {title, body, route} = failed_copy(job)
    create_notification(tenant, job, title, body, route)
  end

  defp create_notification(tenant, %GenerationJob{kind: kind} = job, title, body, route) do
    type = if kind == :image, do: :ai_image, else: :ai_lesson

    Notification
    |> Ash.Changeset.for_create(
      :notify,
      %{
        recipient_id: job.requested_by_id,
        type: type,
        title: title,
        body: body,
        payload: %{generation_job_id: job.id, kind: kind, route: route}
      },
      tenant: tenant,
      authorize?: false
    )
    |> Ash.create()
  rescue
    _ -> :ok
  end

  defp completed_copy(%GenerationJob{kind: :lesson_plan} = job),
    do: {"AI 备课完成", "《#{job.title}》的教案已生成。", "/teacher/ai/lesson-plan"}

  defp completed_copy(%GenerationJob{kind: :image} = job) do
    count = length((job.result || %{})["urls"] || [])
    {"AI 配图完成", "《#{job.title}》已生成 #{count} 张配图。", "/teacher/ai/image"}
  end

  defp failed_copy(%GenerationJob{kind: :lesson_plan} = job),
    do: {"AI 备课失败", "《#{job.title}》生成失败：#{job.error_message || ""}", "/teacher/ai/lesson-plan"}

  defp failed_copy(%GenerationJob{kind: :image} = job),
    do: {"AI 配图失败", "《#{job.title}》生成失败：#{job.error_message || ""}", "/teacher/ai/image"}

  defp broadcast(topic, type, payload) do
    Phoenix.PubSub.broadcast(TcmEdu.PubSub, topic, {:ai_job_event, type, payload})
    :ok
  rescue
    _ -> :ok
  end

  @doc "GenerationJob 状态广播的 PubSub topic。"
  def topic(tenant), do: "ai_jobs:#{tenant}"

  defp payload(%GenerationJob{} = job) do
    %{
      generation_job_id: job.id,
      kind: job.kind,
      title: job.title,
      status: job.status,
      progress: job.progress,
      result: job.result,
      error_message: job.error_message,
      requested_by_id: job.requested_by_id,
      oban_job_id: job.oban_job_id
    }
  end

  defp format_reason(:missing_key), do: "未配置大模型 Key，请联系管理员"
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end
end
