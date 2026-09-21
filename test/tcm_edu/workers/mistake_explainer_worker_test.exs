defmodule TcmEdu.Workers.MistakeExplainerWorkerTest do
  @moduledoc """
  MistakeExplainerWorker 测试：
    * 正确题不上 AI（is_correct: true）→ :ok 且不写 explanation
    * 错题 → 调 AI（mock）→ 写回 Attempt.ai_explanation
    * 缺 attempt_id → 返回 error
  """

  use TcmEdu.DataCase, async: false

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Quiz.{Attempt, Question, QuestionBank}
  alias TcmEdu.Workers.MistakeExplainerWorker

  @tenant "tenant_default"

  setup do
    Application.put_env(:tcm_edu, TcmEdu.AI,
      api_key_override: "sk-test-key",
      base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
      text_model: "qwen-flash",
      timeout: 5_000,
      req_options: [plug: {Req.Test, MistakeExplainerWorkerTest}]
    )

    on_exit(fn ->
      Application.delete_env(:tcm_edu, TcmEdu.AI)
    end)

    :ok
  end

  test "wrong attempt gets AI explanation cached" do
    teacher = create_user!(:teacher)
    student = create_user!(:student)
    {:ok, question} = create_question!(teacher)
    # 错
    {:ok, attempt} = submit!(student, question, "B")

    Req.Test.stub(MistakeExplainerWorkerTest, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "## 错因分析\n丹参不补气。"}}]})
    end)

    job = %Oban.Job{args: %{"attempt_id" => attempt.id, "tenant" => @tenant}}
    assert :ok == MistakeExplainerWorker.perform(job)

    updated = reload_attempt(attempt.id)
    assert updated.ai_explanation =~ "错因分析"
  end

  test "correct attempt is skipped (no AI call, no explanation)" do
    teacher = create_user!(:teacher)
    student = create_user!(:student)
    {:ok, question} = create_question!(teacher)
    # 对
    {:ok, attempt} = submit!(student, question, "A")

    # 若误调 AI 会因为没有 stub 而抛错倒推
    job = %Oban.Job{args: %{"attempt_id" => attempt.id, "tenant" => @tenant}}
    assert :ok == MistakeExplainerWorker.perform(job)

    updated = reload_attempt(attempt.id)
    assert updated.ai_explanation == nil
  end

  test "missing attempt_id returns error" do
    job = %Oban.Job{args: %{"tenant" => @tenant}}
    assert {:error, _} = MistakeExplainerWorker.perform(job)
  end

  # ─── helpers ───────────────────────────────────────────

  defp uniq, do: System.unique_integer([:positive])

  defp create_user!(role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "mew-#{uniq()}@example.com",
        password: "password123",
        role: role
      })
      |> Ash.create(tenant: @tenant, authorize?: false)

    user
  end

  defp create_question!(teacher) do
    {:ok, bank} =
      QuestionBank
      |> Ash.Changeset.for_action(:create, %{name: "Bank #{uniq()}"},
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create()

    Question
    |> Ash.Changeset.for_action(
      :create,
      %{
        type: :single,
        stem: "丹参的功效不包括？",
        options: [
          %{"label" => "A", "text" => "活血祛瘀", "correct" => true},
          %{"label" => "B", "text" => "补气升阳"}
        ],
        answer: "A",
        explanation: "丹参活血祛瘀，不补气。",
        bank_id: bank.id
      },
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.create()
  end

  defp submit!(student, question, answer) do
    Attempt
    |> Ash.Changeset.for_action(:submit, %{question_id: question.id, answer: answer},
      actor: student,
      tenant: @tenant
    )
    |> Ash.create()
  end

  defp reload_attempt(id) do
    Attempt
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one!(tenant: @tenant, authorize?: false)
  end
end
