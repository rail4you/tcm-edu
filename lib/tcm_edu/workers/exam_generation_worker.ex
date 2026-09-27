defmodule TcmEdu.Workers.ExamGenerationWorker do
  @moduledoc """
  Oban worker：执行一次 AI 智能组卷任务。

  流程：

    1. 按 `exam_job_id` + `tenant` 读 `TcmEdu.Exam.ExamJob`，置为 `:running` 并广播；
    2. 加载目标题库的全部有效题目作为候选；
    3. 调用 `TcmEdu.Agents.ExamComposeAction.run/2`（大模型选材 + 确定性兜底）
       得到选中的题目 id；
    4. 创建试卷 `TcmEdu.Exam.Exam`（`source: :ai`），按总分均摊写入
       `TcmEdu.Exam.ExamQuestion`（带分值 / 顺序）；
    5. ExamJob 置为 `:completed`（记录 `exam_id`），广播完成事件并写一条
       `:exam_generated` 站内通知；
    6. 失败则置为 `:failed`，同样广播 + 通知。

  状态广播 topic：`"exam_jobs:<tenant>"`，消息
  `{:exam_job_event, :task_running | :task_completed | :task_failed, payload}`。

  ## 用法

      TcmEdu.Workers.ExamGenerationWorker.new(%{
        "tenant" => "tenant_default",
        "exam_job_id" => exam_job_id
      })
      |> Oban.insert()
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Ash.Query
  require Logger

  alias TcmEdu.Accounts.User
  alias TcmEdu.Agents.ExamComposeAction
  alias TcmEdu.AI.ExamComposer
  alias TcmEdu.Exam.{Exam, ExamJob, ExamQuestion}
  alias TcmEdu.Notification.Notification
  alias TcmEdu.Quiz.Question

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"exam_job_id" => exam_job_id} = args}) do
    tenant = args["tenant"] || "tenant_default"
    topic = topic(tenant)

    with {:ok, job} <- load_job(exam_job_id, tenant),
         :ok <- ensure_pending(job, topic),
         {:ok, running} <- mark(job, :mark_running, %{}, tenant),
         :ok <- broadcast(topic, :task_running, payload(running)) do
      run_compose(running, tenant, topic)
    else
      {:skip, _} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def perform(%Oban.Job{args: args}) do
    {:error, "missing exam_job_id in args: #{inspect(args)}"}
  end

  # ── main flow ─────────────────────────────────────────────

  defp run_compose(%ExamJob{} = job, tenant, topic) do
    actor = load_actor(job, tenant)

    with {:ok, candidates} <- load_candidates(job, tenant),
         {:ok, question_ids} <- compose(job, candidates),
         {:ok, exam} <- create_exam(job, question_ids, actor, tenant) do
      complete(job, tenant, topic, exam)
    else
      {:error, reason} -> fail(job, tenant, topic, reason)
    end
  end

  defp compose(%ExamJob{} = job, candidates) do
    params = %{
      candidates: candidates,
      topic: job.topic,
      subject: job.subject || "中医",
      count: job.question_count || 5,
      question_types: job.question_types || ["single"],
      difficulty: job.difficulty,
      knowledge_points: job.knowledge_points || [],
      requirements: nil
    }

    case ExamComposeAction.run(params, %{}) do
      {:ok, %{question_ids: ids}} when is_list(ids) ->
        if ids == [] do
          {:error, "组卷未选出任何题目"}
        else
          {:ok, ids}
        end

      other ->
        {:error, "组卷失败：#{inspect(other)}"}
    end
  end

  defp load_candidates(%ExamJob{bank_id: bank_id}, tenant) do
    questions =
      Question
      |> Ash.Query.filter(bank_id == ^bank_id and status == :active)
      |> Ash.read(tenant: tenant, authorize?: false)
      |> case do
        {:ok, list} -> list
        _ -> []
      end

    candidates =
      Enum.map(questions, fn q ->
        %{
          id: q.id,
          stem: q.stem,
          type: q.type,
          difficulty: q.difficulty || 3,
          knowledge_points: q.knowledge_points || []
        }
      end)

    if candidates == [] do
      {:error, "目标题库没有可用题目，请先向题库中添加习题"}
    else
      {:ok, candidates}
    end
  end

  defp create_exam(%ExamJob{} = job, question_ids, actor, tenant) do
    scores = ExamComposer.distribute_scores(question_ids, job.total_score || 100)

    attrs = %{
      name: job.name,
      description: job.description,
      subject: subject_atom(job.subject),
      source: :ai,
      duration_minutes: 60
    }

    with {:ok, exam} <- persist_exam(attrs, actor, tenant) do
      results =
        question_ids
        |> Enum.with_index(1)
        |> Enum.map(fn {question_id, index} ->
          create_exam_question(exam, question_id, index, scores[question_id], actor, tenant)
        end)

      errors = for {:error, reason} <- results, do: reason

      cond do
        length(errors) == length(question_ids) ->
          {:error, "试卷题目写入失败：#{Enum.join(errors, "；")}"}

        true ->
          warning = if errors == [], do: nil, else: "（#{length(errors)} 题写入失败）"

          Logger.info(
            "[ExamGenerationWorker] exam=#{exam.id} composed #{length(question_ids)} questions#{warning || ""}"
          )

          {:ok, %{exam: exam, warning: warning}}
      end
    end
  end

  defp persist_exam(attrs, actor, tenant) do
    if actor do
      Exam.create_exam(attrs, actor: actor, tenant: tenant)
    else
      Exam
      |> Ash.Changeset.for_create(:create, attrs, tenant: tenant, authorize?: false)
      |> Ash.create()
    end
  end

  defp create_exam_question(%Exam{} = exam, question_id, position, score, actor, tenant) do
    attrs = %{
      exam_id: exam.id,
      question_id: question_id,
      position: position,
      score: score || Decimal.new(1)
    }

    if actor do
      ExamQuestion.create_exam_question(attrs, actor: actor, tenant: tenant)
    else
      ExamQuestion
      |> Ash.Changeset.for_create(:create, attrs, tenant: tenant, authorize?: false)
      |> Ash.create()
    end
  end

  # ── terminal states ───────────────────────────────────────

  defp complete(%ExamJob{} = job, tenant, topic, %{exam: exam, warning: warning}) do
    with {:ok, done} <-
           mark(job, :mark_completed, %{exam_id: exam.id}, tenant) do
      broadcast(topic, :task_completed, payload(done))

      notify(
        tenant,
        job,
        "AI 组卷完成",
        "《#{exam.name}》已生成 #{job.question_count || "?"} 道题#{warning || ""}，可进入试卷分配学生。"
      )

      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp fail(%ExamJob{} = job, tenant, topic, reason) do
    message = truncate(to_string(reason), 500)
    Logger.warning("[ExamGenerationWorker] job=#{job.id} failed: #{message}")

    with {:ok, failed} <- mark(job, :mark_failed, %{error_message: message}, tenant) do
      broadcast(topic, :task_failed, payload(failed))
      notify(tenant, job, "AI 组卷失败", "《#{job.name}》组卷失败：#{message}")
      :ok
    else
      _ -> :ok
    end
  end

  # ── loading ───────────────────────────────────────────────

  defp load_job(id, tenant) do
    case ExamJob
         |> Ash.Query.filter(id == ^id)
         |> Ash.Query.limit(1)
         |> Ash.read_one(tenant: tenant, authorize?: false) do
      {:ok, %ExamJob{} = job} -> {:ok, job}
      other -> {:error, "exam job not found: #{inspect(other)}"}
    end
  end

  defp ensure_pending(%ExamJob{status: :completed}, _topic), do: {:skip, :already_done}
  defp ensure_pending(%ExamJob{status: :failed}, _topic), do: {:skip, :failed_awaiting_retry}
  defp ensure_pending(%ExamJob{}, _topic), do: :ok

  defp load_actor(%ExamJob{requested_by_id: nil}, _tenant), do: nil

  defp load_actor(%ExamJob{requested_by_id: user_id}, tenant) do
    case Ash.get(User, user_id, tenant: tenant, authorize?: false) do
      {:ok, %User{} = user} -> user
      _ -> nil
    end
  end

  defp mark(%ExamJob{} = job, action, params, tenant) do
    job
    |> Ash.Changeset.for_update(action, params)
    |> Ash.update(tenant: tenant, authorize?: false)
  end

  # ── notify + broadcast ────────────────────────────────────

  defp notify(tenant, %ExamJob{} = job, title, body) do
    Notification
    |> Ash.Changeset.for_create(
      :notify,
      %{
        recipient_id: job.requested_by_id,
        type: :exam_generated,
        title: title,
        body: body,
        payload: %{exam_job_id: job.id, route: "/teacher/exams"}
      },
      tenant: tenant,
      authorize?: false
    )
    |> Ash.create()
  rescue
    _ -> :ok
  end

  defp broadcast(topic, type, payload) do
    Phoenix.PubSub.broadcast(TcmEdu.PubSub, topic, {:exam_job_event, type, payload})
    :ok
  rescue
    _ -> :ok
  end

  @doc "ExamJob 状态广播的 PubSub topic。"
  def topic(tenant), do: "exam_jobs:#{tenant}"

  defp payload(%ExamJob{} = job) do
    %{
      exam_job_id: job.id,
      bank_id: job.bank_id,
      exam_id: job.exam_id,
      name: job.name,
      status: job.status,
      error_message: job.error_message,
      requested_by_id: job.requested_by_id
    }
  end

  defp subject_atom(subject) when is_binary(subject) do
    case subject do
      "西医" -> :western_medicine
      "解剖" -> :anatomy
      "生理" -> :physiology
      "病理" -> :pathology
      "药理" -> :pharmacology
      "临床" -> :clinical
      "护理" -> :nursing
      "公卫" -> :public_health
      "其他" -> :other
      _ -> :traditional_chinese_medicine
    end
  end

  defp subject_atom(_), do: :traditional_chinese_medicine

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end
end
