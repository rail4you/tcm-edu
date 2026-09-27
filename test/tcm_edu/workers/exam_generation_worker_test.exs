defmodule TcmEdu.Workers.ExamGenerationWorkerTest do
  @moduledoc """
  ExamGenerationWorker 测试（Qwen 经 Req.Test mock / 无 key 走确定性兜底）：

    * LLM 成功选材 → 创建试卷 + ExamQuestions（分值均摊）→ Job completed
    * LLM 非法/失败 → 回退确定性兜底 → 仍能完成组卷
    * 题库无题 → Job failed
    * 已完成的任务重复执行 → 跳过，不重复建卷
    * 缺 exam_job_id → 返回 error
  """

  use TcmEdu.DataCase, async: false

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Exam.{Exam, ExamJob, ExamQuestion}
  alias TcmEdu.Notification.Notification
  alias TcmEdu.Quiz.{Question, QuestionBank}
  alias TcmEdu.Workers.ExamGenerationWorker

  @tenant "tenant_default"

  setup do
    Application.put_env(:tcm_edu, TcmEdu.AI,
      api_key_override: "sk-test-key",
      base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
      text_model: "qwen-flash",
      timeout: 5_000,
      req_options: [plug: {Req.Test, ExamGenerationWorkerTest}]
    )

    on_exit(fn -> Application.delete_env(:tcm_edu, TcmEdu.AI) end)

    :ok
  end

  test "LLM selection creates a published-capable exam and completes the job" do
    teacher = create_user!(:teacher)
    bank = create_bank_with_questions!(teacher, 3)
    {:ok, job} = request_job!(teacher, bank, "AI 组卷", 3)

    Req.Test.stub(ExamGenerationWorkerTest, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [
          %{
            "message" => %{
              "content" => Jason.encode!(%{"question_ids" => [h1(bank).id, h2(bank).id]})
            }
          }
        ]
      })
    end)

    assert :ok == ExamGenerationWorker.perform(oban_job(job.id))

    done = reload_job(job.id)
    assert done.status == :completed
    assert done.exam_id != nil

    exam =
      Exam
      |> Ash.Query.filter(id == ^done.exam_id)
      |> Ash.Query.load([:exam_questions, :total_questions, :total_score])
      |> Ash.read_one!(tenant: @tenant, authorize?: false)

    assert exam.name == "AI 组卷"
    assert exam.source == :ai
    assert exam.total_questions == 2
    assert exam.created_by_id == teacher.id

    assert [%ExamQuestion{position: 1, score: s1}, %ExamQuestion{position: 2, score: s2}] =
             exam.exam_questions

    assert Decimal.add(s1, s2) |> Decimal.to_string() == "100.00"

    assert [%Notification{type: :exam_generated, recipient_id: recipient}] =
             Notification
             |> Ash.Query.filter(recipient_id == ^teacher.id)
             |> Ash.read!(tenant: @tenant, authorize?: false)

    assert recipient == teacher.id
  end

  test "LLM invalid output falls back to deterministic selection" do
    teacher = create_user!(:teacher)
    bank = create_bank_with_questions!(teacher, 4)
    {:ok, job} = request_job!(teacher, bank, "兜底组卷", 3)

    Req.Test.stub(ExamGenerationWorkerTest, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "不是 JSON"}}]})
    end)

    assert :ok == ExamGenerationWorker.perform(oban_job(job.id))

    done = reload_job(job.id)
    assert done.status == :completed
    assert done.exam_id != nil
  end

  test "bank without questions fails the job" do
    teacher = create_user!(:teacher)
    bank = create_bank!(teacher)
    {:ok, job} = request_job!(teacher, bank, "空题库", 3)

    assert :ok == ExamGenerationWorker.perform(oban_job(job.id))

    failed = reload_job(job.id)
    assert failed.status == :failed
    assert failed.error_message =~ "没有可用题目"
  end

  test "completed job is not executed twice" do
    teacher = create_user!(:teacher)
    bank = create_bank_with_questions!(teacher, 2)
    {:ok, job} = request_job!(teacher, bank, "幂等组卷", 2)

    Req.Test.stub(ExamGenerationWorkerTest, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "坏 JSON"}}]})
    end)

    assert :ok == ExamGenerationWorker.perform(oban_job(job.id))
    assert :ok == ExamGenerationWorker.perform(oban_job(job.id))

    done = reload_job(job.id)
    assert done.status == :completed

    assert length(
             Exam
             |> Ash.Query.filter(id == ^done.exam_id)
             |> Ash.read!(tenant: @tenant, authorize?: false)
           ) == 1
  end

  test "missing exam_job_id returns error" do
    assert {:error, _} = ExamGenerationWorker.perform(%Oban.Job{args: %{"tenant" => @tenant}})
  end

  # ─── helpers ───────────────────────────────────────────

  defp uniq, do: System.unique_integer([:positive])

  defp oban_job(exam_job_id) do
    %Oban.Job{args: %{"exam_job_id" => exam_job_id, "tenant" => @tenant}}
  end

  defp create_user!(role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "examw-#{uniq()}@example.com",
        password: "password123",
        role: role
      })
      |> Ash.create(tenant: @tenant, authorize?: false)

    user
  end

  defp create_bank!(teacher) do
    {:ok, bank} =
      QuestionBank
      |> Ash.Changeset.for_action(:create, %{name: "ExamWBank #{uniq()}"},
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create()

    bank
  end

  defp create_bank_with_questions!(teacher, count) do
    bank = create_bank!(teacher)

    for i <- 1..count do
      Question.create_question!(
        %{
          bank_id: bank.id,
          type: :single,
          difficulty: 3,
          stem: "组卷候选#{i}",
          options: [
            %{label: "A", text: "甲", correct: true},
            %{label: "B", text: "乙", correct: false}
          ]
        },
        actor: teacher,
        tenant: @tenant
      )
    end

    bank
  end

  defp h1(bank), do: questions(bank) |> Enum.at(0)
  defp h2(bank), do: questions(bank) |> Enum.at(1)

  defp questions(bank) do
    Question
    |> Ash.Query.filter(bank_id == ^bank.id)
    |> Ash.read!(tenant: @tenant, authorize?: false)
  end

  defp request_job!(teacher, bank, name, count) do
    ExamJob.request_exam_job(
      %{
        name: name,
        bank_id: bank.id,
        topic: "肺经腧穴",
        subject: "中医基础",
        question_count: count,
        question_types: ["single"],
        difficulty: 3,
        knowledge_points: ["肺经"],
        total_score: 100,
        requested_by_id: teacher.id,
        requested_by_email: to_string(teacher.email)
      },
      actor: teacher,
      tenant: @tenant
    )
  end

  defp reload_job(id) do
    ExamJob |> Ash.Query.filter(id == ^id) |> Ash.read_one!(tenant: @tenant, authorize?: false)
  end
end
