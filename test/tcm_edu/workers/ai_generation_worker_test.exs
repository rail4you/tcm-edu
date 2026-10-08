defmodule TcmEdu.Workers.AiGenerationWorkerTest do
  @moduledoc """
  AiGenerationWorker 测试（Qwen 经 Req.Test mock，不触达真实 DashScope）：

    * 成功 → 备课结果落库 → GenerationJob completed（progress 100）+ 通知
    * 未配置 Key → GenerationJob failed（worker 返回 :ok，不触发 Oban 重试）
    * 已完成的任务重复执行 → 直接跳过
    * 缺 generation_job_id → 返回 error
  """

  use TcmEdu.DataCase, async: false

  require Ash.Query

  alias TcmEdu.AI.GenerationJob
  alias TcmEdu.Accounts.User
  alias TcmEdu.Notification.Notification
  alias TcmEdu.Workers.AiGenerationWorker

  @tenant "tenant_default"

  setup do
    Application.put_env(:tcm_edu, TcmEdu.AI,
      api_key_override: "sk-test-key",
      base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
      text_model: "qwen-flash",
      timeout: 5_000,
      req_options: [plug: {Req.Test, AiGenerationWorkerTest}]
    )

    on_exit(fn -> Application.delete_env(:tcm_edu, TcmEdu.AI) end)

    :ok
  end

  test "successful lesson plan generation completes the job and notifies" do
    teacher = create_user!(:teacher)
    {:ok, job} = request_job!(teacher, :lesson_plan, "手太阴肺经腧穴")

    Req.Test.stub(AiGenerationWorkerTest, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => "# 教学目标\n掌握肺经循行"}}]
      })
    end)

    assert :ok == AiGenerationWorker.perform(oban_job(job.id))

    done = reload_job(job.id)
    assert done.status == :completed
    assert done.progress == 100
    assert done.result["plan"] =~ "肺经"

    assert [%Notification{type: :ai_lesson, recipient_id: recipient}] =
             Notification
             |> Ash.Query.filter(recipient_id == ^teacher.id)
             |> Ash.read!(tenant: @tenant, authorize?: false)

    assert recipient == teacher.id
  end

  test "missing key marks the job failed without raising" do
    Application.put_env(:tcm_edu, TcmEdu.AI, api_key_override: :none)

    teacher = create_user!(:teacher)
    {:ok, job} = request_job!(teacher, :lesson_plan, "无密钥主题")

    assert :ok == AiGenerationWorker.perform(oban_job(job.id))

    failed = reload_job(job.id)
    assert failed.status == :failed
    assert failed.error_message =~ "Key"
  end

  test "already completed job is skipped" do
    teacher = create_user!(:teacher)
    {:ok, job} = request_job!(teacher, :lesson_plan, "重复主题")

    job
    |> Ash.Changeset.for_update(:mark_completed, %{result: %{"plan" => "旧结果"}})
    |> Ash.update!(tenant: @tenant, authorize?: false)

    assert :ok == AiGenerationWorker.perform(oban_job(job.id))
    assert reload_job(job.id).result == %{"plan" => "旧结果"}
  end

  test "missing generation_job_id returns error" do
    assert {:error, _} = AiGenerationWorker.perform(%Oban.Job{args: %{}})
  end

  # ─── helpers ───

  defp uniq, do: System.unique_integer([:positive])

  defp oban_job(job_id) do
    %Oban.Job{args: %{"generation_job_id" => job_id, "tenant" => @tenant}}
  end

  defp create_user!(role) do
    User
    |> Ash.Changeset.for_action(:register_with_role, %{
      email: "aigen-#{uniq()}@example.com",
      password: "password123",
      role: role
    })
    |> Ash.create!(tenant: @tenant, authorize?: false)
  end

  defp request_job!(teacher, kind, title) do
    GenerationJob.request_generation_job(
      %{
        kind: kind,
        title: title,
        params: %{"subject" => "中医基础", "level" => "本科", "audience" => "大一"},
        requested_by_id: teacher.id,
        requested_by_email: to_string(teacher.email)
      },
      actor: teacher,
      tenant: @tenant
    )
  end

  defp reload_job(id) do
    GenerationJob
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one!(tenant: @tenant, authorize?: false)
  end
end
