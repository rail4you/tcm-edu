defmodule TcmEduWeb.TeacherAIJobsTest do
  @moduledoc """
  任务管理页（`/teacher/ai/jobs`）PhoenixTest 覆盖：

    * 默认只看我的任务；可切换看到同租户他人的任务
    * 按状态筛选
    * 失败任务重试（重新入队）
    * 删除任务记录（两步确认）
  """

  use TcmEduWeb.LiveViewCase

  import Oban.Testing, only: [assert_enqueued: 1]
  import PhoenixTest

  require Ash.Query

  alias TcmEdu.AI.GenerationJob
  alias TcmEdu.Accounts.User
  alias TcmEdu.Quiz.{QuestionBank, QuizJob}
  alias TcmEdu.Workers.{AiGenerationWorker, QuizGenerationWorker}

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher = create_teacher!(" jobs-a-")
    other = create_teacher!(" jobs-b-")

    bank =
      QuestionBank
      |> Ash.Changeset.for_create(
        :create,
        %{name: "任务管理库#{System.unique_integer([:positive])}"},
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create!()

    {:ok, completed} = request_job(teacher, bank, "A完成主题")

    completed
    |> Ash.Changeset.for_update(:mark_completed, %{generated_count: 2, question_ids: []})
    |> Ash.update!(tenant: @tenant, authorize?: false)

    {:ok, failed} = request_job(teacher, bank, "A失败主题")

    failed
    |> Ash.Changeset.for_update(:mark_failed, %{error_message: "模型超时"})
    |> Ash.update!(tenant: @tenant, authorize?: false)

    {:ok, _other_job} = request_job(other, bank, "B待办主题")

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "Jobs Teacher"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, teacher: teacher, bank: bank, failed: failed, completed: completed}
  end

  test "lists only my jobs by default", %{conn: conn} do
    conn
    |> visit("/teacher/ai/jobs")
    |> assert_has("td", "A完成主题")
    |> assert_has("td", "A失败主题")
    |> refute_has("td", "B待办主题")
  end

  test "filters by status", %{conn: conn} do
    conn
    |> visit("/teacher/ai/jobs")
    |> select("状态", option: "失败")
    |> assert_has("td", "A失败主题")
    |> refute_has("td", "A完成主题")
    |> select("状态", option: "全部")
    |> assert_has("td", "A完成主题")
    |> assert_has("td", "A失败主题")
  end

  test "unchecking mine-only reveals tenant jobs", %{conn: conn} do
    conn
    |> visit("/teacher/ai/jobs")
    |> uncheck("只看我的")
    |> assert_has("td", "B待办主题")
  end

  test "retry re-enqueues a failed job", %{conn: conn, failed: failed} do
    conn
    |> visit("/teacher/ai/jobs")
    |> click_button("#retry-job-#{failed.id}", "重试")
    |> assert_has("p", "已重新提交", exact: false)

    reset = reload_job(failed.id)
    assert reset.status == :pending

    assert_enqueued(
      worker: QuizGenerationWorker,
      args: %{"tenant" => @tenant, "quiz_job_id" => failed.id},
      repo: TcmEdu.Repo
    )
  end

  test "delete removes the record after confirmation", %{conn: conn, completed: completed} do
    conn
    |> visit("/teacher/ai/jobs")
    |> click_button("#delete-job-#{completed.id}", "删除")
    |> click_button("确认删除")
    |> assert_has("p", "任务记录已删除")
    |> refute_has("td", "A完成主题")
  end

  test "lists generation jobs and retries a failed one", %{conn: conn, teacher: teacher} do
    {:ok, job} = create_gen_job(teacher, "备课任务")

    job
    |> Ash.Changeset.for_update(:mark_failed, %{error_message: "模型超时"})
    |> Ash.update!(tenant: @tenant, authorize?: false)

    conn
    |> visit("/teacher/ai/jobs")
    |> assert_has("#generation-job-#{job.id}")
    |> assert_has("td", "备课任务")
    |> assert_has("td", "备课")
    |> click_button("#retry-job-#{job.id}", "重试")
    |> assert_has("p", "已重新提交", exact: false)

    assert reload_gen_job(job.id).status == :pending

    assert_enqueued(
      worker: AiGenerationWorker,
      args: %{"tenant" => @tenant, "generation_job_id" => job.id},
      repo: TcmEdu.Repo
    )
  end

  # ─── helpers ───────────────────────────────────────────

  defp create_teacher!(infix) do
    User
    |> Ash.Changeset.for_create(
      :register_with_role,
      %{
        email: "ai#{infix}#{System.unique_integer([:positive])}@example.com",
        name: "Jobs Teacher",
        password: "password123",
        role: :teacher
      },
      tenant: @tenant,
      authorize?: false
    )
    |> Ash.create!()
  end

  defp request_job(teacher, bank, topic) do
    QuizJob.request_quiz_job(
      %{
        bank_id: bank.id,
        topic: topic,
        question_count: 2,
        question_types: ["single"],
        difficulty: 3,
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

  defp create_gen_job(teacher, title) do
    GenerationJob.request_generation_job(
      %{
        kind: :lesson_plan,
        title: title,
        params: %{},
        requested_by_id: teacher.id,
        requested_by_email: to_string(teacher.email)
      },
      actor: teacher,
      tenant: @tenant
    )
  end

  defp reload_gen_job(id) do
    GenerationJob
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one!(tenant: @tenant, authorize?: false)
  end
end
