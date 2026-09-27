defmodule TcmEdu.Exam.ScoreCalculator do
  @moduledoc """
  考试计分（租户域，纯计算）。

  约定：

    * 客观题答对 → `response.score` = 该题分值；答错 → 0
    * 主观题（简答）→ `response.is_correct` 为 nil；教师批改后 `graded = true`
      且 `score` 为手动给分
    * `objective_score` = 客观题得分之和（`is_correct == true` 的 score 求和）
    * `essay_score`     = 主观题已批改得分之和（`graded == true` 的 score 求和）
    * `total_score`     = objective + essay

  `compute/2` 对某作答下的所有答案求和，供交卷 / 批改 / 逐题批注后重算总分。
  """

  require Ash.Query

  alias TcmEdu.Exam.ExamResponse

  @doc """
  计算某作答的客观 / 主观 / 总分。

  ## 参数

    * `assignment_id` — ExamAssignment id
    * `tenant`        — schema（`"tenant_<slug>"`）

  ## 返回

  `%{objective_score: Decimal.t, essay_score: Decimal.t, total_score: Decimal.t}`
  """
  @spec compute(Ecto.UUID.t(), String.t()) :: map()
  def compute(assignment_id, tenant) do
    responses =
      ExamResponse
      |> Ash.Query.filter(assignment_id == ^assignment_id)
      |> Ash.read(tenant: tenant, authorize?: false)
      |> case do
        {:ok, list} -> list
        _ -> []
      end

    objective =
      responses
      |> Enum.filter(&(&1.is_correct == true))
      |> sum_scores()

    essay =
      responses
      |> Enum.filter(&(&1.graded == true))
      |> sum_scores()

    total = Decimal.add(objective, essay)

    %{
      objective_score: objective,
      essay_score: essay,
      total_score: total
    }
  end

  defp sum_scores(list) do
    Enum.reduce(list, Decimal.new(0), fn response, acc ->
      case response.score do
        %Decimal{} = score -> Decimal.add(acc, score)
        score when is_number(score) -> Decimal.add(acc, Decimal.new(score))
        nil -> acc
      end
    end)
  end
end
