defmodule TcmEduWeb.TeacherAIQuizTest do
  @moduledoc """
  AI 出题页（`/teacher/ai/quiz`）PhoenixTest 覆盖：

    * 提交需求 → QuizJob 落库（pending）+ Oban 入队 + 列表出现"排队中"
    * 已完成的任务在进入页面时展示成功 banner，可关闭
    * 失败任务可在本页重试
  """

  use TcmEduWeb.LiveViewCase

  import Oban.Testing, only: [assert_enqueued: 1]
  import PhoenixTest

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Quiz.{QuestionBank, QuizJob}
  alias TcmEdu.Workers.QuizGenerationWorker

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "ai-quiz-#{System.unique_integer([:positive])}@example.com",
          name: "AI Quiz Teacher",
          password: "password123",
          role: :teacher
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    bank =
      QuestionBank
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "AI出题库#{System.unique_integer([:positive])}",
          subject: :traditional_chinese_medicine
        },
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create!()

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "AI Quiz Teacher"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, teacher: teacher, bank: bank}
  end

  test "submit enqueues Oban job and lists it as pending", %{
    conn: conn,
    teacher: teacher,
    bank: bank
  } do
    conn
    |> visit("/teacher/ai/quiz")
    |> select("目标题库", option: bank.name)
    |> fill_in("主题", with: "肺经腧穴定位")
    |> click_button("开始生成")
    |> assert_has("p", "已提交后台生成", exact: false)
    |> assert_has("li[id^='quiz-job-']", text: "肺经腧穴定位")
    |> assert_has("span", "排队中")

    [job] = my_jobs(teacher)
    assert job.topic == "肺经腧穴定位"
    assert job.status == :pending

    assert_enqueued(
      worker: QuizGenerationWorker,
      args: %{"tenant" => @tenant, "quiz_job_id" => job.id},
      repo: TcmEdu.Repo
    )
  end

  test "completed job shows a banner that can be dismissed", %{
    conn: conn,
    teacher: teacher,
    bank: bank
  } do
    {:ok, job} = request_job(teacher, bank, "横幅主题")

    job
    |> Ash.Changeset.for_update(:mark_completed, %{generated_count: 3, question_ids: []})
    |> Ash.update!(tenant: @tenant, authorize?: false)

    conn
    |> visit("/teacher/ai/quiz")
    |> assert_has("#quiz-done-banner", "横幅主题")
    |> assert_has("#banner-goto-quiz-btn", "查看题库")
    |> click_button("#banner-dismiss-btn", "关闭")
    |> refute_has("#quiz-done-banner")
  end

  test "failed job can be retried from the page", %{conn: conn, teacher: teacher, bank: bank} do
    {:ok, job} = request_job(teacher, bank, "重试主题")

    job
    |> Ash.Changeset.for_update(:mark_failed, %{error_message: "模型超时"})
    |> Ash.update!(tenant: @tenant, authorize?: false)

    conn
    |> visit("/teacher/ai/quiz")
    |> assert_has("span", "失败")
    |> click_button("#retry-job-#{job.id}", "重试")
    |> assert_has("p", "已重新提交", exact: false)

    reset = reload_job(job.id)
    assert reset.status == :pending

    assert_enqueued(
      worker: QuizGenerationWorker,
      args: %{"tenant" => @tenant, "quiz_job_id" => job.id},
      repo: TcmEdu.Repo
    )
  end

  # ─── helpers ───────────────────────────────────────────

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

  defp my_jobs(teacher) do
    QuizJob
    |> Ash.Query.for_read(:list_mine, %{requested_by_id: teacher.id},
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.read!()
  end

  defp reload_job(id) do
    QuizJob |> Ash.Query.filter(id == ^id) |> Ash.read_one!(tenant: @tenant, authorize?: false)
  end
end
