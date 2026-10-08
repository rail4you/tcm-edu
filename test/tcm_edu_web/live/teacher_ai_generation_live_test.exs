defmodule TcmEduWeb.TeacherAIGenerationLiveTest do
  @moduledoc """
  AI 备课 / AI 配图页的 Oban 化覆盖（`/teacher/ai/lesson-plan`、
  `/teacher/ai/image`）：

    * 提交后创建 `TcmEdu.AI.GenerationJob` 并入队 `AiGenerationWorker`；
    * 页面显示任务进度（`#lesson-progress` / `#image-progress`）；
    * 离开再返回页面时，从库里恢复已完成任务的结果；
    * 已完成任务在「AI 任务管理」列表中可见。
  """

  use TcmEduWeb.LiveViewCase

  import Oban.Testing, only: [assert_enqueued: 1]
  import PhoenixTest

  require Ash.Query

  alias TcmEdu.AI.GenerationJob
  alias TcmEdu.Accounts.User
  alias TcmEdu.Workers.AiGenerationWorker

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher = create_teacher!()

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "AI Gen Teacher"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, teacher: teacher}
  end

  describe "lesson plan" do
    test "submitting enqueues a job and shows progress", %{conn: conn, teacher: teacher} do
      conn
      |> visit("/teacher/ai/lesson-plan")
      |> fill_in("主题", with: "手太阴肺经腧穴")
      |> click_button("生成教案")
      |> assert_has("p", "已提交后台生成", exact: false)
      |> assert_has("#lesson-progress")

      job = latest_job(teacher.id, :lesson_plan)
      assert job
      assert job.status == :pending

      assert_enqueued(
        worker: AiGenerationWorker,
        args: %{"tenant" => @tenant, "generation_job_id" => job.id},
        repo: TcmEdu.Repo
      )
    end

    test "returning to the page restores a completed plan", %{conn: conn, teacher: teacher} do
      {:ok, _job} =
        create_job(teacher, :lesson_plan, "阴阳五行", %{"plan" => "# 教学目标\n理解阴阳学说"})

      conn
      |> visit("/teacher/ai/lesson-plan")
      |> assert_has("main", "阴阳五行")
      |> assert_has("#plan-row-0")
      |> assert_has("#plan-detail-0")
      |> refute_has("#lesson-progress")
    end

    test "one-row table whose detail renders markdown with heading nav", %{
      conn: conn,
      teacher: teacher
    } do
      plan = "# 教学目标\n\n掌握阴阳学说的基本内容\n\n## 重点难点\n\n阴阳的对立与互根"

      {:ok, _job} = create_job(teacher, :lesson_plan, "阴阳五行", %{"plan" => plan})

      conn
      |> visit("/teacher/ai/lesson-plan")
      |> assert_has("#plan-row-0")
      |> refute_has("#plan-row-1")
      |> click_button("#plan-detail-0", "详情")
      |> assert_has(".modal.modal-open h1", "教学目标")
      |> assert_has(".modal.modal-open", "掌握阴阳学说的基本内容")
      |> assert_has("nav[aria-label='教案导航']", "重点难点")
    end
  end

  describe "image" do
    test "submitting enqueues a job and shows progress", %{conn: conn, teacher: teacher} do
      conn
      |> visit("/teacher/ai/image")
      |> fill_in("画面描述", with: "手太阴肺经循行示意图")
      |> click_button("生成配图")
      |> assert_has("p", "已提交后台生成", exact: false)
      |> assert_has("#image-progress")

      job = latest_job(teacher.id, :image)
      assert job

      assert_enqueued(
        worker: AiGenerationWorker,
        args: %{"tenant" => @tenant, "generation_job_id" => job.id},
        repo: TcmEdu.Repo
      )
    end

    test "returning to the page restores completed images", %{conn: conn, teacher: teacher} do
      {:ok, _job} =
        create_job(teacher, :image, "肺经图", %{
          "urls" => ["https://example.com/lung-1.png", "https://example.com/lung-2.png"]
        })

      conn
      |> visit("/teacher/ai/image")
      |> assert_has("img[src='https://example.com/lung-1.png']")
      |> assert_has("img[src='https://example.com/lung-2.png']")
      |> refute_has("#image-progress")
    end
  end

  test "completed generation task appears in the AI jobs list", %{
    conn: conn,
    teacher: teacher
  } do
    {:ok, job} =
      create_job(teacher, :image, "任务管理可见性", %{"urls" => ["https://example.com/x.png"]})

    conn
    |> visit("/teacher/ai/jobs")
    |> assert_has("#generation-job-#{job.id}")
    |> assert_has("td", "任务管理可见性")
    |> assert_has("td", "配图")
  end

  # ─── helpers ───

  defp uniq, do: System.unique_integer([:positive])

  defp create_teacher! do
    User
    |> Ash.Changeset.for_create(
      :register_with_role,
      %{
        email: "aigen-live-#{uniq()}@example.com",
        name: "AI Gen Teacher",
        password: "password123",
        role: :teacher
      },
      tenant: @tenant,
      authorize?: false
    )
    |> Ash.create!()
  end

  defp create_job(teacher, kind, title, result) do
    with {:ok, job} <-
           GenerationJob.request_generation_job(
             %{
               kind: kind,
               title: title,
               params: %{},
               requested_by_id: teacher.id,
               requested_by_email: to_string(teacher.email)
             },
             actor: teacher,
             tenant: @tenant
           ) do
      job
      |> Ash.Changeset.for_update(:mark_completed, %{result: result})
      |> Ash.update(tenant: @tenant, authorize?: false)
    end
  end

  defp latest_job(requested_by_id, kind) do
    GenerationJob
    |> Ash.Query.for_read(:latest_mine, %{requested_by_id: requested_by_id, kind: kind},
      tenant: @tenant,
      authorize?: false
    )
    |> Ash.read_one!()
  end
end
