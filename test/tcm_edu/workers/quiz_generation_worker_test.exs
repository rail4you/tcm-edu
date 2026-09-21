defmodule TcmEdu.Workers.QuizGenerationWorkerTest do
  @moduledoc """
  QuizGenerationWorker 测试（Qwen 经 Req.Test mock，不触达真实 DashScope）：

    * 成功 → Jido Action 生成 + 校验 → 题目入库 → QuizJob completed + 通知
    * 非法 JSON → QuizJob failed（worker 返回 :ok，不触发 Oban 重试导致重复入库）
    * 已完成的任务重复执行 → 直接跳过，不重复入库
    * 缺 quiz_job_id → 返回 error
  """

  use TcmEdu.DataCase, async: false

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Notification.Notification
  alias TcmEdu.Quiz.{Question, QuestionBank, QuizJob}
  alias TcmEdu.Workers.QuizGenerationWorker

  @tenant "tenant_default"

  setup do
    Application.put_env(:tcm_edu, TcmEdu.AI,
      api_key_override: "sk-test-key",
      base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
      text_model: "qwen-flash",
      timeout: 5_000,
      req_options: [plug: {Req.Test, QuizGenerationWorkerTest}]
    )

    on_exit(fn -> Application.delete_env(:tcm_edu, TcmEdu.AI) end)

    :ok
  end

  test "successful generation persists questions and completes the job" do
    teacher = create_user!(:teacher)
    bank = create_bank!(teacher)
    {:ok, job} = request_job!(teacher, bank, "肺经腧穴")

    Req.Test.stub(QuizGenerationWorkerTest, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => llm_payload()}}]
      })
    end)

    assert :ok == QuizGenerationWorker.perform(oban_job(job.id))

    done = reload_job(job.id)
    assert done.status == :completed
    assert done.generated_count == 2
    assert length(done.question_ids) == 2

    questions =
      Question
      |> Ash.Query.filter(bank_id == ^bank.id)
      |> Ash.read!(tenant: @tenant, authorize?: false)

    assert length(questions) == 2
    assert Enum.map(questions, & &1.stem) |> Enum.sort() == ["JUDGE题干", "SINGLE题干"]
    assert Enum.all?(questions, &(&1.created_by_id == teacher.id))

    assert [%Notification{type: :quiz_generated, recipient_id: recipient}] =
             Notification
             |> Ash.Query.filter(recipient_id == ^teacher.id)
             |> Ash.read!(tenant: @tenant, authorize?: false)

    assert recipient == teacher.id
  end

  test "invalid LLM json marks the job failed without raising" do
    teacher = create_user!(:teacher)
    bank = create_bank!(teacher)
    {:ok, job} = request_job!(teacher, bank, "坏数据主题")

    Req.Test.stub(QuizGenerationWorkerTest, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "这不是 JSON"}}]})
    end)

    assert :ok == QuizGenerationWorker.perform(oban_job(job.id))

    failed = reload_job(job.id)
    assert failed.status == :failed
    assert failed.error_message =~ "JSON"

    assert [] =
             Question
             |> Ash.Query.filter(bank_id == ^bank.id)
             |> Ash.read!(tenant: @tenant, authorize?: false)
  end

  test "completed job is not executed twice" do
    teacher = create_user!(:teacher)
    bank = create_bank!(teacher)
    {:ok, job} = request_job!(teacher, bank, "幂等主题")

    Req.Test.stub(QuizGenerationWorkerTest, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => llm_payload()}}]
      })
    end)

    assert :ok == QuizGenerationWorker.perform(oban_job(job.id))

    # 若误调 AI 会因为 stub 已被消费一次之外的调用仍可响应；关键是第二次直接 skip
    assert :ok == QuizGenerationWorker.perform(oban_job(job.id))

    assert length(
             Question
             |> Ash.Query.filter(bank_id == ^bank.id)
             |> Ash.read!(tenant: @tenant, authorize?: false)
           ) == 2
  end

  test "missing quiz_job_id returns error" do
    assert {:error, _} = QuizGenerationWorker.perform(%Oban.Job{args: %{"tenant" => @tenant}})
  end

  # ─── helpers ───────────────────────────────────────────

  defp uniq, do: System.unique_integer([:positive])

  defp oban_job(quiz_job_id) do
    %Oban.Job{args: %{"quiz_job_id" => quiz_job_id, "tenant" => @tenant}}
  end

  defp create_user!(role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "qgen-#{uniq()}@example.com",
        password: "password123",
        role: role
      })
      |> Ash.create(tenant: @tenant, authorize?: false)

    user
  end

  defp create_bank!(teacher) do
    {:ok, bank} =
      QuestionBank
      |> Ash.Changeset.for_action(:create, %{name: "AI Bank #{uniq()}"},
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create()

    bank
  end

  defp request_job!(teacher, bank, topic) do
    QuizJob.request_quiz_job(
      %{
        bank_id: bank.id,
        topic: topic,
        subject: "中医基础",
        question_count: 2,
        question_types: ["single", "judge"],
        difficulty: 3,
        knowledge_points: ["肺经"],
        requested_by_id: teacher.id,
        requested_by_email: to_string(teacher.email)
      },
      actor: teacher,
      tenant: @tenant
    )
  end

  defp reload_job(id) do
    QuizJob |> Ash.Query.filter(id == ^id) |> Ash.read_one!(tenant: @tenant, authorize?: false)
  end

  defp llm_payload do
    Jason.encode!([
      %{
        "type" => "single",
        "stem" => "SINGLE题干",
        "options" => [
          %{"label" => "A", "text" => "甲", "correct" => true},
          %{"label" => "B", "text" => "乙", "correct" => false}
        ],
        "answer" => "A",
        "explanation" => "解析",
        "difficulty" => 3,
        "knowledge_points" => ["肺经"]
      },
      %{
        "type" => "judge",
        "stem" => "JUDGE题干",
        "answer" => "对",
        "explanation" => "解析",
        "difficulty" => 2,
        "knowledge_points" => []
      }
    ])
  end
end
