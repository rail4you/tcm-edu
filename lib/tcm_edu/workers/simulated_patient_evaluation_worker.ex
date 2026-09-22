defmodule TcmEdu.Workers.SimulatedPatientEvaluationWorker do
  @moduledoc """
  Oban worker：对一次模拟诊疗会话生成 AI 评分。

  ## 流程

    1. 按 `session_id` + `tenant` 加载 `SimulatedPatient.Session`，把 `evaluation_status` 置为 `:running`；
    2. 加载该 session 的全部消息（学生 vs 病人），拼成 transcript；
    3. 调 `TcmEdu.AI.SimulatedPatientEvaluator.evaluate/1`；
    4. 写入 `TcmEdu.SimulatedPatient.Evaluation`，并把 session 的 `evaluation_status` 置为 `:completed`；
    5. 给学生写一条站内通知（type `:simulated_patient_evaluated`），让顶栏红点出现；
    6. 失败则把 `evaluation_status` 置为 `:failed` 并记录错误信息，同样发通知。

  ## PubSub

  Worker 完成后向 `"simulated_patient_sessions:<tenant>"` 广播
  `{:simulated_patient_session_event, :evaluation_completed | :evaluation_failed, payload}`，
  学生端 LiveView 订阅后从「评分中」刷新到「评分已出」。

  ## 用法

      TcmEdu.Workers.SimulatedPatientEvaluationWorker.new(%{
        "tenant" => "tenant_default",
        "session_id" => session_id
      })
      |> Oban.insert()
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Ash.Query
  require Logger

  alias TcmEdu.AI.SimulatedPatientEvaluator
  alias TcmEdu.Notification.Notification
  alias TcmEdu.SimulatedPatient.{Evaluation, Message, Session}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"session_id" => session_id} = args}) do
    tenant = args["tenant"] || "tenant_default"
    topic = topic(tenant)

    with {:ok, session} <- load_session(session_id, tenant),
         :ok <- ensure_eligible(session),
         {:ok, running} <- set_status(session, :running, nil, tenant),
         :ok <- broadcast(topic, :evaluation_running, payload(running)) do
      run_evaluation(running, tenant, topic)
    else
      {:skip, reason} ->
        Logger.info("[SimulatedPatientEvaluationWorker] skip session=#{session_id}: #{reason}")
        :ok

      {:error, reason} ->
        Logger.error("[SimulatedPatientEvaluationWorker] failed to start: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end

  def perform(%Oban.Job{args: args}) do
    {:error, "missing session_id in args: #{inspect(args)}"}
  end

  # ── main flow ─────────────────────────────────────────────

  defp run_evaluation(%Session{} = session, tenant, topic) do
    transcript = load_transcript(session, tenant)

    case SimulatedPatientEvaluator.evaluate(
           patient_snapshot: session.patient_snapshot,
           transcript: transcript,
           tenant: tenant
         ) do
      {:ok, attrs} ->
        persist_and_notify(session, attrs, tenant, topic)

      {:error, reason} ->
        fail(session, tenant, topic, to_string(reason))
    end
  end

  defp persist_and_notify(%Session{} = session, attrs, tenant, topic) do
    Evaluation
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{
        session_id: session.id,
        patient_id: session.patient_id,
        student_id: session.student_id
      }),
      tenant: tenant,
      authorize?: false
    )
    |> Ash.create()
    |> case do
      {:ok, evaluation} ->
        case set_status(session, :completed, nil, tenant) do
          {:ok, done} ->
            broadcast(topic, :evaluation_completed, payload(done, evaluation.id))
            notify_student(session, evaluation, tenant)
            :ok

          err ->
            Logger.error("[SimulatedPatientEvaluationWorker] set_status failed: #{inspect(err)}")

            :ok
        end

      {:error, reason} ->
        fail(session, tenant, topic, "写入评分失败：#{inspect(reason)}")
    end
  end

  defp fail(%Session{} = session, tenant, topic, reason) do
    Logger.warning("[SimulatedPatientEvaluationWorker] session=#{session.id} failed: #{reason}")

    case set_status(session, :failed, reason, tenant) do
      {:ok, failed} ->
        broadcast(topic, :evaluation_failed, payload(failed))
        notify_failure(session, tenant, reason)

      _ ->
        :ok
    end

    :ok
  end

  # ── loading ───────────────────────────────────────────────

  defp load_session(id, tenant) do
    case Session
         |> Ash.Query.filter(id == ^id)
         |> Ash.Query.limit(1)
         |> Ash.read_one(tenant: tenant, authorize?: false) do
      {:ok, %Session{} = session} -> {:ok, session}
      other -> {:error, "session not found: #{inspect(other)}"}
    end
  end

  defp load_transcript(%Session{id: session_id}, tenant) do
    Message
    |> Ash.Query.for_read(:for_session, %{session_id: session_id})
    |> Ash.read(tenant: tenant, authorize?: false)
    |> case do
      {:ok, messages} ->
        Enum.map(messages, fn m -> %{role: m.role, content: m.content} end)

      err ->
        Logger.warning(
          "[SimulatedPatientEvaluationWorker] failed to load transcript: #{inspect(err)}"
        )

        []
    end
  end

  defp ensure_eligible(%Session{status: :completed, evaluation_status: :completed}),
    do: {:skip, "already_evaluated"}

  defp ensure_eligible(%Session{status: :active}),
    do: {:skip, "session_still_active"}

  defp ensure_eligible(%Session{}), do: :ok

  defp set_status(%Session{} = session, status, error, tenant) do
    params =
      case error do
        nil -> %{evaluation_status: status}
        reason -> %{evaluation_status: status, evaluation_error: reason}
      end

    session
    |> Ash.Changeset.for_update(:set_evaluation_status, params)
    |> Ash.update(tenant: tenant, authorize?: false)
  end

  # ── broadcast / notify ────────────────────────────────────

  defp notify_student(%Session{} = session, %Evaluation{} = eval, tenant) do
    body =
      "已完成模拟诊疗评分：总分 #{Decimal.to_string(eval.total_score, :normal)}（#{grade_label(eval.grade)}）"

    Notification
    |> Ash.Changeset.for_create(
      :notify,
      %{
        recipient_id: session.student_id,
        type: :simulated_patient_evaluated,
        title: "AI 模拟诊疗评分已出",
        body: body,
        payload: %{
          session_id: session.id,
          evaluation_id: eval.id,
          total_score: Decimal.to_string(eval.total_score, :normal),
          grade: to_string(eval.grade),
          route: "/simulated-patient/sessions/#{session.id}"
        }
      },
      tenant: tenant,
      authorize?: false
    )
    |> Ash.create()
  rescue
    e ->
      Logger.warning("[SimulatedPatientEvaluationWorker] notify failed: #{Exception.message(e)}")

      :ok
  end

  defp notify_failure(%Session{} = session, tenant, reason) do
    Notification
    |> Ash.Changeset.for_create(
      :notify,
      %{
        recipient_id: session.student_id,
        type: :simulated_patient_evaluated,
        title: "AI 模拟诊疗评分失败",
        body: "评分失败：#{truncate(reason, 120)}。请稍后重试或联系教师。",
        payload: %{session_id: session.id, route: "/simulated-patient/sessions/#{session.id}"}
      },
      tenant: tenant,
      authorize?: false
    )
    |> Ash.create()
  rescue
    _ -> :ok
  end

  defp broadcast(topic, type, payload) do
    Phoenix.PubSub.broadcast(
      TcmEdu.PubSub,
      topic,
      {:simulated_patient_session_event, type, payload}
    )

    :ok
  rescue
    _ -> :ok
  end

  @doc "Simulated patient session PubSub topic."
  def topic(tenant), do: "simulated_patient_sessions:#{tenant}"

  defp payload(%Session{} = session, evaluation_id \\ nil) do
    %{
      session_id: session.id,
      patient_id: session.patient_id,
      student_id: session.student_id,
      evaluation_status: session.evaluation_status,
      evaluation_id: evaluation_id
    }
  end

  defp grade_label(:excellent), do: "优秀"
  defp grade_label(:good), do: "良好"
  defp grade_label(:pass), do: "及格"
  defp grade_label(:borderline), do: "边缘"
  defp grade_label(:fail), do: "不及格"
  defp grade_label(other), do: to_string(other)

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end
end
