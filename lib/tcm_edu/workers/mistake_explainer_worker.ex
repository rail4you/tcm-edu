defmodule TcmEdu.Workers.MistakeExplainerWorker do
  @moduledoc """
  Oban worker：对一道错题调 AI 解析，结果缓存回 `Attempt.ai_explanation`。

  由外部按需 enqueue（如学员点「AI 解析」按钮或错误提交后异步触发），
  worker 内加载 Attempt + Question，调 `TcmEdu.AI.MistakeExplainer`，
  成功后写入 `Attempt.cache_ai_explanation`。

  ## 用法

      TcmEdu.Workers.MistakeExplainerWorker.new(%{
        "tenant" => "tenant_default",
        "attempt_id" => attempt_id
      })
      |> Oban.insert()
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Ash.Query

  alias TcmEdu.AI.MistakeExplainer
  alias TcmEdu.Quiz.{Attempt, Question}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attempt_id" => attempt_id} = args}) do
    tenant = args["tenant"] || "tenant_default"

    with {:ok, attempt} <- load_attempt(attempt_id, tenant),
         :ok <- ensure_wrong(attempt),
         {:ok, question} <- load_question(attempt.question_id, tenant),
         {:ok, content} <- MistakeExplainer.explain(question_to_map(question), attempt.answer) do
      cache_explanation(attempt, content, tenant)
    else
      {:skip, _} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def perform(%Oban.Job{args: args}) do
    {:error, "missing attempt_id in args: #{inspect(args)}"}
  end

  defp load_attempt(id, tenant) do
    case Attempt
         |> Ash.Query.filter(id == ^id)
         |> Ash.Query.limit(1)
         |> Ash.read_one(tenant: tenant, authorize?: false) do
      {:ok, %Attempt{} = a} -> {:ok, a}
      other -> {:error, "attempt not found: #{inspect(other)}"}
    end
  end

  # 只有答错的题才解释
  defp ensure_wrong(%Attempt{is_correct: false}), do: :ok
  defp ensure_wrong(%Attempt{is_correct: nil}), do: {:skip, :not_graded}
  defp ensure_wrong(_), do: {:skip, :already_correct}

  defp load_question(id, tenant) do
    case Question
         |> Ash.Query.filter(id == ^id)
         |> Ash.Query.limit(1)
         |> Ash.read_one(tenant: tenant, authorize?: false) do
      {:ok, %Question{} = q} -> {:ok, q}
      other -> {:error, "question not found: #{inspect(other)}"}
    end
  end

  # Question struct → MistakeExplainer 需要的 map
  defp question_to_map(%Question{} = q) do
    %{
      type: to_string(q.type),
      stem: q.stem,
      options: q.options,
      answer: q.answer,
      explanation: q.explanation
    }
  end

  defp cache_explanation(%Attempt{} = attempt, content, tenant) do
    case attempt
         |> Ash.Changeset.for_update(:cache_ai_explanation, %{ai_explanation: content})
         |> Ash.update(tenant: tenant, authorize?: false) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, inspect(error)}
    end
  end
end
