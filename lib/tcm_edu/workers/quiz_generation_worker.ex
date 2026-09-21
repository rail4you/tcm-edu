defmodule TcmEdu.Workers.QuizGenerationWorker do
  @moduledoc """
  Oban worker：执行一次 AI 出题任务。

  流程：

    1. 按 `quiz_job_id` + `tenant` 读 `TcmEdu.Quiz.QuizJob`，置为 `:running` 并广播；
    2. 调用 Jido agent 工具 `TcmEdu.Agents.QuizQuestionAction.run/2`
       （LLM 生成 + `TcmEdu.AI.QuizValidator` 结构化验证）；
    3. 把验证通过的题目逐条写入目标题库（`TcmEdu.Quiz.Question`）；
    4. QuizJob 置为 `:completed`（记录 `generated_count` / `question_ids`），
       广播完成事件，并写一条 `:quiz_generated` 站内通知；
    5. 失败则置为 `:failed`（记录 `error_message`），同样广播 + 通知。

  状态广播 topic：`"quiz_jobs:<tenant>"`，消息
  `{:quiz_job_event, :task_running | :task_completed | :task_failed, payload}`。
  payload 恒带 `requested_by_id`，LiveView 据此只展示自己的 banner。

  Worker 与任何 LiveView 进程无关，教师提交后离开页面不影响生成。

  ## 用法

      TcmEdu.Workers.QuizGenerationWorker.new(%{
        "tenant" => "tenant_default",
        "quiz_job_id" => quiz_job_id
      })
      |> Oban.insert()
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Ash.Query
  require Logger

  alias TcmEdu.Accounts.User
  alias TcmEdu.Agents.QuizQuestionAction
  alias TcmEdu.Notification.Notification
  alias TcmEdu.Quiz.{Question, QuizJob}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"quiz_job_id" => quiz_job_id} = args}) do
    tenant = args["tenant"] || "tenant_default"
    topic = topic(tenant)

    with {:ok, job} <- load_job(quiz_job_id, tenant),
         :ok <- ensure_pending(job, topic),
         {:ok, running} <- mark(job, :mark_running, %{}, tenant),
         :ok <- broadcast(topic, :task_running, payload(running)) do
      run_generation(running, tenant, topic)
    else
      {:skip, _} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def perform(%Oban.Job{args: args}) do
    {:error, "missing quiz_job_id in args: #{inspect(args)}"}
  end

  # ── main flow ──────────────────────────────────────────────

  defp run_generation(%QuizJob{} = job, tenant, topic) do
    actor = load_actor(job, tenant)

    case generate_questions(job) do
      {:ok, []} ->
        fail(job, tenant, topic, "AI 没有返回可用题目，请调整主题后重试")

      {:ok, items} ->
        persist_questions(job, items, actor, tenant, topic)

      {:error, reason} ->
        fail(job, tenant, topic, reason)
    end
  end

  defp generate_questions(%QuizJob{} = job) do
    params = %{
      topic: job.topic,
      subject: job.subject || "中医",
      count: job.question_count || 5,
      question_types: job.question_types || ["single"],
      difficulty: job.difficulty || 3,
      knowledge_points: job.knowledge_points || [],
      requirements: job.requirements
    }

    case QuizQuestionAction.run(params, %{}) do
      {:ok, %{questions: questions}} when is_list(questions) -> {:ok, questions}
      {:ok, other} -> {:error, "Agent 返回格式异常：#{inspect(other)}"}
      {:error, reason} -> {:error, to_string(reason)}
    end
  end

  defp persist_questions(%QuizJob{} = job, items, actor, tenant, topic) do
    {ids, errors} =
      Enum.reduce(items, {[], []}, fn attrs, {ok_ids, errs} ->
        case create_question(job, attrs, actor, tenant) do
          {:ok, question} -> {[question.id | ok_ids], errs}
          {:error, error} -> {ok_ids, [ash_message(error) | errs]}
        end
      end)

    ids = Enum.reverse(ids)

    cond do
      ids == [] ->
        fail(job, tenant, topic, "题目全部写入失败：#{Enum.join(errors, "；")}")

      true ->
        warning = if errors == [], do: nil, else: "（#{length(errors)} 题写入失败）"
        complete(job, tenant, topic, ids, warning)
    end
  end

  defp create_question(%QuizJob{} = job, attrs, actor, tenant) do
    params = Map.put(attrs, :bank_id, job.bank_id)

    if actor do
      Question.create_question(params, actor: actor, tenant: tenant)
    else
      Question
      |> Ash.Changeset.for_create(:create, params, tenant: tenant, authorize?: false)
      |> Ash.create()
    end
  end

  # ── terminal states ────────────────────────────────────────

  defp complete(%QuizJob{} = job, tenant, topic, ids, warning) do
    with {:ok, done} <-
           mark(job, :mark_completed, %{generated_count: length(ids), question_ids: ids}, tenant) do
      broadcast(topic, :task_completed, payload(done))

      notify(
        tenant,
        job,
        "AI 出题完成",
        "《#{job.topic}》已生成 #{length(ids)} 道习题#{warning || ""}，已写入目标题库。"
      )

      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp fail(%QuizJob{} = job, tenant, topic, reason) do
    message = truncate(to_string(reason), 500)
    Logger.warning("[QuizGenerationWorker] job=#{job.id} failed: #{message}")

    with {:ok, failed} <- mark(job, :mark_failed, %{error_message: message}, tenant) do
      broadcast(topic, :task_failed, payload(failed))
      notify(tenant, job, "AI 出题失败", "《#{job.topic}》生成失败：#{message}")
      :ok
    else
      _ -> :ok
    end
  end

  # ── loading ────────────────────────────────────────────────

  defp load_job(id, tenant) do
    case QuizJob
         |> Ash.Query.filter(id == ^id)
         |> Ash.Query.limit(1)
         |> Ash.read_one(tenant: tenant, authorize?: false) do
      {:ok, %QuizJob{} = job} -> {:ok, job}
      other -> {:error, "quiz job not found: #{inspect(other)}"}
    end
  end

  # 幂等：已完成的不重复执行；失败的只能通过页面重试（重新入队）。
  defp ensure_pending(%QuizJob{status: :completed}, _topic), do: {:skip, :already_done}
  defp ensure_pending(%QuizJob{status: :failed}, _topic), do: {:skip, :failed_awaiting_retry}
  defp ensure_pending(%QuizJob{}, _topic), do: :ok

  defp load_actor(%QuizJob{requested_by_id: nil}, _tenant), do: nil

  defp load_actor(%QuizJob{requested_by_id: user_id}, tenant) do
    case Ash.get(User, user_id, tenant: tenant, authorize?: false) do
      {:ok, %User{} = user} -> user
      _ -> nil
    end
  end

  # Worker 是后台进程：内部状态流转不带 actor（authorize?: false），
  # 与 ChatTask / LongTaskWorker 的做法一致。对外（LiveView）的
  # set_oban_job / retry 仍走 policy，由调用方传 actor。
  defp mark(%QuizJob{} = job, action, params, tenant) do
    job
    |> Ash.Changeset.for_update(action, params)
    |> Ash.update(tenant: tenant, authorize?: false)
  end

  # ── notify + broadcast ─────────────────────────────────────

  defp notify(tenant, %QuizJob{} = job, title, body) do
    Notification
    |> Ash.Changeset.for_create(
      :notify,
      %{
        recipient_id: job.requested_by_id,
        type: :quiz_generated,
        title: title,
        body: body,
        payload: %{quiz_job_id: job.id, bank_id: job.bank_id, route: "/teacher/quiz"}
      },
      tenant: tenant,
      authorize?: false
    )
    |> Ash.create()
  rescue
    _ -> :ok
  end

  defp broadcast(topic, type, payload) do
    Phoenix.PubSub.broadcast(TcmEdu.PubSub, topic, {:quiz_job_event, type, payload})
    :ok
  rescue
    _ -> :ok
  end

  @doc "QuizJob 状态广播的 PubSub topic。"
  def topic(tenant), do: "quiz_jobs:#{tenant}"

  defp payload(%QuizJob{} = job) do
    %{
      quiz_job_id: job.id,
      bank_id: job.bank_id,
      topic: job.topic,
      status: job.status,
      generated_count: job.generated_count,
      question_ids: job.question_ids,
      error_message: job.error_message,
      requested_by_id: job.requested_by_id,
      oban_job_id: job.oban_job_id
    }
  end

  defp ash_message(error) do
    error |> Exception.message() |> String.split("\n") |> hd() |> String.trim() |> truncate(120)
  rescue
    _ -> "未知错误"
  end

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end
end
