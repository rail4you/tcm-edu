defmodule TcmEduWeb.JsonApi.StudentJsonApiTest do
  @moduledoc """
  学员端 JSON:API（`/api/student/*`，由 `AshJsonApi` 从 Ash DSL 生成）。

  覆盖：
    * 认证闸门 —— 无 token / 坏 token 一律 401（`RequireAuth`）
    * 6 个读接口：overview、我的选课、学习进度、通知、测验记录、课程目录
    * 3 个写接口：选课、课时进度 upsert、全部标记已读
    * 课程目录与详情 `?include=chapters.lessons`
    * 属主隔离：只能看到/改到自己的数据
  """

  use TcmEduWeb.ConnCase, async: false

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Courses.{Chapter, Course, CourseCategory, Lesson}
  alias TcmEdu.Enrollment.{Enrollment, Progress}
  alias TcmEdu.Exam.{Exam, ExamAssignment}
  alias TcmEdu.Notification.Notification
  alias TcmEduWeb.AuthToken

  @tenant "tenant_default"
  @jsonapi "application/vnd.api+json"

  setup do
    teacher = create_user!(:teacher)
    student = create_user!(:student)
    other = create_user!(:student)
    course = create_published_course!(teacher, "JSON:API 入门")

    %{teacher: teacher, student: student, other: other, course: course}
  end

  # ─── 认证 ────────────────────────────────────────────────────────

  describe "authentication" do
    test "no bearer token -> 401", %{conn: conn} do
      conn = api_get(conn, "/api/student/enrollments")
      assert json_response(conn, 401) == %{"error" => "Not authenticated"}
    end

    test "garbage bearer token -> 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer not-a-jwt")
        |> api_get("/api/student/enrollments")

      assert json_response(conn, 401) == %{"error" => "Not authenticated"}
    end

    test "token whose subject no longer exists -> 401", %{conn: conn} do
      # 签名合法但 sub 指向一个不存在的用户：SetTenantFromToken 找不到 actor，
      # 下游必须当成未登录处理，而不是放行成匿名。
      {:ok, token, _claims} =
        AuthToken.generate(Ecto.UUID.generate(), %{"tenant" => @tenant, "role" => "student"})

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> api_get("/api/student/enrollments")

      assert json_response(conn, 401) == %{"error" => "Not authenticated"}
    end
  end

  # ─── overview ────────────────────────────────────────────────────

  describe "GET /api/student/enrollments/overview" do
    test "returns the six homepage stats", %{
      conn: conn,
      teacher: teacher,
      student: student,
      course: course
    } do
      enroll!(student, course)
      notify!(teacher, recipient_id: student.id, title: "A")
      notify!(teacher, recipient_id: student.id, title: "B")

      body =
        conn
        |> auth(student)
        |> api_get("/api/student/enrollments/overview")
        |> json_response(200)

      assert body == %{
               "enrolled_courses" => 1,
               "completed_lessons" => 0,
               "study_seconds" => 0,
               "streak_days" => 0,
               "mistakes" => 0,
               "unread_notifications" => 2
             }
    end

    test "only counts my own data", %{
      conn: conn,
      teacher: teacher,
      student: student,
      other: other,
      course: course
    } do
      enroll!(other, course)
      notify!(teacher, recipient_id: other.id, title: "Not mine")

      body =
        conn
        |> auth(student)
        |> api_get("/api/student/enrollments/overview")
        |> json_response(200)

      assert body["enrolled_courses"] == 0
      assert body["unread_notifications"] == 0
    end
  end

  # ─── 我的选课 ────────────────────────────────────────────────────

  describe "GET /api/student/enrollments" do
    test "lists only my enrollments", %{
      conn: conn,
      student: student,
      other: other,
      course: course
    } do
      enroll!(student, course)
      enroll!(other, course)

      %{"data" => data} =
        conn
        |> auth(student)
        |> api_get("/api/student/enrollments")
        |> json_response(200)

      assert length(data) == 1
      assert hd(data)["type"] == "enrollment"
      assert hd(data)["attributes"]["status"] == "active"
    end

    test "include=course sideloads the course", %{conn: conn, student: student, course: course} do
      enroll!(student, course)

      body =
        conn
        |> auth(student)
        |> api_get("/api/student/enrollments?include=course")
        |> json_response(200)

      assert get_in(hd(body["data"]), ["relationships", "course", "data"]) == %{
               "type" => "course",
               "id" => course.id
             }

      assert [%{"type" => "course", "id" => included_id}] = included_of_type(body, "course")
      assert included_id == course.id
    end
  end

  # ─── 选课 ────────────────────────────────────────────────────────

  describe "POST /api/student/enrollments" do
    test "enrolls me in a published course", %{conn: conn, student: student, course: course} do
      conn =
        conn
        |> auth(student)
        |> api_post("/api/student/enrollments", %{
          "data" => %{"type" => "enrollment", "attributes" => %{"course_id" => course.id}}
        })

      assert %{"data" => %{"type" => "enrollment", "id" => id, "attributes" => attrs}} =
               json_response(conn, 201)

      assert attrs["user_id"] == student.id
      assert attrs["course_id"] == course.id
      assert attrs["status"] == "active"

      assert {:ok, %Enrollment{}} = Ash.get(Enrollment, id, actor: student, tenant: @tenant)
    end

    test "plain application/json request body -> 415", %{
      conn: conn,
      student: student,
      course: course
    } do
      # JSON:API 只接受 application/vnd.api+json：漏掉媒体类型必须显式拒绝，
      # 而不是静默按 JSON 解析（客户端换错 content-type 时才看得出来）
      conn =
        conn
        |> auth(student)
        |> put_req_header("accept", @jsonapi)
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/student/enrollments",
          Jason.encode!(%{
            "data" => %{"type" => "enrollment", "attributes" => %{"course_id" => course.id}}
          })
        )

      assert conn.status == 415
      assert %{"errors" => [_ | _]} = json_response(conn, 415)
    end

    test "rejects a duplicate enrollment", %{conn: conn, student: student, course: course} do
      enroll!(student, course)

      conn =
        conn
        |> auth(student)
        |> api_post("/api/student/enrollments", %{
          "data" => %{"type" => "enrollment", "attributes" => %{"course_id" => course.id}}
        })

      refute conn.status in 200..299
      assert %{"errors" => [_ | _]} = json_response(conn, conn.status)
    end
  end

  # ─── 学习进度 ────────────────────────────────────────────────────

  describe "GET/POST /api/student/progress" do
    test "upserts by (enrollment, lesson) and updates the same row", %{
      conn: conn,
      student: student,
      course: course
    } do
      enrollment = enroll!(student, course)
      lesson = first_lesson!(course)

      first =
        conn
        |> auth(student)
        |> api_post("/api/student/progress", %{
          "data" => %{
            "type" => "progress",
            "attributes" => %{
              "enrollment_id" => enrollment.id,
              "lesson_id" => lesson.id,
              "status" => "in_progress",
              "progress_pct" => 40,
              "last_position_seconds" => 240
            }
          }
        })
        |> json_response(201)

      second =
        conn
        |> auth(student)
        |> api_post("/api/student/progress", %{
          "data" => %{
            "type" => "progress",
            "attributes" => %{
              "enrollment_id" => enrollment.id,
              "lesson_id" => lesson.id,
              "status" => "in_progress",
              "progress_pct" => 100,
              "last_position_seconds" => 600
            }
          }
        })
        |> json_response(201)

      assert first["data"]["id"] == second["data"]["id"]
      assert second["data"]["attributes"]["progress_pct"] == 100

      # progress_pct >= 100 由 Changes.AutoComplete 落 completed
      assert second["data"]["attributes"]["status"] == "completed"
      assert second["data"]["attributes"]["completed_at"]

      assert [row] =
               conn
               |> auth(student)
               |> api_get("/api/student/progress")
               |> json_response(200)
               |> Map.fetch!("data")

      assert row["id"] == first["data"]["id"]
    end

    test "a later in_progress write rewrites status/pct but not completed_at", %{
      conn: conn,
      student: student,
      course: course
    } do
      enrollment = enroll!(student, course)
      lesson = first_lesson!(course)

      done =
        conn
        |> auth(student)
        |> api_post("/api/student/progress", %{
          "data" => %{
            "type" => "progress",
            "attributes" => %{
              "enrollment_id" => enrollment.id,
              "lesson_id" => lesson.id,
              "status" => "completed",
              "progress_pct" => 100,
              "last_position_seconds" => 600
            }
          }
        })
        |> json_response(201)

      assert done["data"]["attributes"]["completed_at"]

      # upsert_fields 只覆盖 status / progress_pct / last_position_seconds：
      # 回退进度不得抹掉已完成的时间戳，否则"最近学完"统计会被冲掉
      regressed =
        conn
        |> auth(student)
        |> api_post("/api/student/progress", %{
          "data" => %{
            "type" => "progress",
            "attributes" => %{
              "enrollment_id" => enrollment.id,
              "lesson_id" => lesson.id,
              "status" => "in_progress",
              "progress_pct" => 40,
              "last_position_seconds" => 240
            }
          }
        })
        |> json_response(201)

      attrs = regressed["data"]["attributes"]
      assert regressed["data"]["id"] == done["data"]["id"]
      assert attrs["status"] == "in_progress"
      assert attrs["progress_pct"] == 40
      assert attrs["completed_at"] == done["data"]["attributes"]["completed_at"]
    end

    test "lists only my progress records", %{
      conn: conn,
      student: student,
      other: other,
      course: course
    } do
      my_enrollment = enroll!(student, course)
      other_enrollment = enroll!(other, course)
      lesson = first_lesson!(course)

      for enrollment <- [my_enrollment, other_enrollment] do
        {:ok, _} =
          Progress
          |> Ash.Changeset.for_action(
            :upsert_progress,
            %{enrollment_id: enrollment.id, lesson_id: lesson.id, progress_pct: 10},
            actor: if(enrollment.id == my_enrollment.id, do: student, else: other),
            tenant: @tenant
          )
          |> Ash.create()
      end

      %{"data" => data} =
        conn
        |> auth(student)
        |> api_get("/api/student/progress")
        |> json_response(200)

      assert length(data) == 1
      assert hd(data)["attributes"]["enrollment_id"] == my_enrollment.id
    end
  end

  # ─── 通知 ────────────────────────────────────────────────────────

  describe "GET/POST /api/student/notifications" do
    test "lists only my notifications", %{
      conn: conn,
      teacher: teacher,
      student: student,
      other: other
    } do
      notify!(teacher, recipient_id: student.id, title: "Mine")
      notify!(teacher, recipient_id: other.id, title: "Not mine")

      %{"data" => data} =
        conn
        |> auth(student)
        |> api_get("/api/student/notifications")
        |> json_response(200)

      assert length(data) == 1
      assert hd(data)["attributes"]["title"] == "Mine"
      assert hd(data)["attributes"]["read_at"] == nil
    end

    test "exposes inserted_at for client-side timestamps", %{
      conn: conn,
      teacher: teacher,
      student: student
    } do
      notify!(teacher, recipient_id: student.id, title: "Stamped")

      %{"data" => [row]} =
        conn
        |> auth(student)
        |> api_get("/api/student/notifications")
        |> json_response(200)

      # 时间列表按 inserted_at 排，客户端据此渲染"今天 01:41"
      assert is_binary(row["attributes"]["inserted_at"])
      assert row["attributes"]["read_at"] == nil
    end

    test "mark_all_read only marks my own", %{
      conn: conn,
      teacher: teacher,
      student: student,
      other: other
    } do
      notify!(teacher, recipient_id: student.id, title: "A")
      notify!(teacher, recipient_id: student.id, title: "B")
      notify!(teacher, recipient_id: other.id, title: "Other")

      conn =
        conn
        |> auth(student)
        |> api_post("/api/student/notifications/mark_all_read", %{})

      assert json_response(conn, 201) == %{"updated" => 2}

      mine = unread_titles(student)
      assert mine == []
      assert unread_titles(other) == ["Other"]
    end
  end

  # ─── 测验记录 ────────────────────────────────────────────────────

  describe "GET /api/student/exam-assignments" do
    test "lists only my exam records", %{
      conn: conn,
      teacher: teacher,
      student: student,
      other: other
    } do
      {:ok, exam} = create_exam!(teacher, "JSON API 测验")
      {:ok, _} = publish!(exam, teacher)

      for s <- [student, other] do
        {:ok, _} =
          ExamAssignment.assign_exam(%{exam_id: exam.id, student_id: s.id},
            actor: teacher,
            tenant: @tenant
          )
      end

      %{"data" => data} =
        conn
        |> auth(student)
        |> api_get("/api/student/exam-assignments")
        |> json_response(200)

      assert length(data) == 1
      assert hd(data)["attributes"]["exam_id"] == exam.id
      assert hd(data)["attributes"]["status"] == "assigned"
    end

    test "include=exam sideloads the exam the client renders in the row", %{
      conn: conn,
      teacher: teacher,
      student: student
    } do
      {:ok, exam} = create_exam!(teacher, "带 include 的测验")
      {:ok, _} = publish!(exam, teacher)

      {:ok, _} =
        ExamAssignment.assign_exam(%{exam_id: exam.id, student_id: student.id},
          actor: teacher,
          tenant: @tenant
        )

      body =
        conn
        |> auth(student)
        |> api_get("/api/student/exam-assignments?include=exam")
        |> json_response(200)

      assert [%{"type" => "exam", "id" => id}] = included_of_type(body, "exam")
      assert id == exam.id

      assert get_in(hd(body["data"]), ["relationships", "exam", "data"]) == %{
               "type" => "exam",
               "id" => exam.id
             }
    end
  end

  # ─── 课程目录 ────────────────────────────────────────────────────

  describe "GET /api/student/courses" do
    test "lists published courses and skips drafts", %{
      conn: conn,
      teacher: teacher,
      student: student,
      course: course
    } do
      {:ok, draft} =
        Course
        |> Ash.Changeset.for_action(:create_course, %{
          title: "草稿课 #{System.unique_integer([:positive])}",
          teacher_id: teacher.id
        })
        |> Ash.create(actor: teacher, tenant: @tenant)

      body =
        conn
        |> auth(student)
        |> api_get("/api/student/courses")
        |> json_response(200)

      ids = Enum.map(body["data"], & &1["id"])

      assert course.id in ids
      refute draft.id in ids
    end

    test "includes chapters.lessons when asked", %{conn: conn, student: student} do
      body =
        conn
        |> auth(student)
        |> api_get("/api/student/courses?include=chapters.lessons")
        |> json_response(200)

      assert [%{"type" => "chapter"} | _] = included_of_type(body, "chapter")
      assert [%{"type" => "lesson"} | _] = included_of_type(body, "lesson")
    end

    test "include=category sideloads typed course categories", %{
      conn: conn,
      teacher: teacher,
      student: student,
      course: course
    } do
      {:ok, category} =
        CourseCategory
        |> Ash.Changeset.for_action(:create, %{
          name: "中医基础",
          slug: "basics-#{uniq()}"
        })
        |> Ash.create(tenant: @tenant, authorize?: false)

      {:ok, course} =
        course
        |> Ash.Changeset.for_update(:update, %{category_id: category.id})
        |> Ash.update(actor: teacher, tenant: @tenant, authorize?: false)

      body =
        conn
        |> auth(student)
        |> api_get("/api/student/courses?include=category")
        |> json_response(200)

      # 没有 AshJsonApi.Resource 的资源会序列化成 type: null，客户端无法按 type 索引
      assert [included] = included_of_type(body, "course_category")
      assert included["id"] == category.id
      assert included["attributes"]["name"] == "中医基础"

      row = Enum.find(body["data"], &(&1["id"] == course.id))

      assert get_in(row, ["relationships", "category", "data"]) == %{
               "type" => "course_category",
               "id" => category.id
             }
    end

    test "include=category on the detail route too", %{
      conn: conn,
      teacher: teacher,
      student: student,
      course: course
    } do
      {:ok, category} =
        CourseCategory
        |> Ash.Changeset.for_action(:create, %{
          name: "临床实践",
          slug: "clinical-#{uniq()}"
        })
        |> Ash.create(tenant: @tenant, authorize?: false)

      {:ok, _course} =
        course
        |> Ash.Changeset.for_update(:update, %{category_id: category.id})
        |> Ash.update(actor: teacher, tenant: @tenant, authorize?: false)

      body =
        conn
        |> auth(student)
        |> api_get("/api/student/courses/#{course.id}?include=category")
        |> json_response(200)

      assert [%{"type" => "course_category", "id" => id}] =
               included_of_type(body, "course_category")

      assert id == category.id
    end

    test "no bearer token -> 401", %{conn: conn} do
      conn = api_get(conn, "/api/student/courses")
      assert json_response(conn, 401) == %{"error" => "Not authenticated"}
    end
  end

  # ─── 课程详情 ────────────────────────────────────────────────────

  describe "GET /api/student/courses/:id" do
    test "returns the course with chapters.lessons", %{
      conn: conn,
      student: student,
      course: course
    } do
      body =
        conn
        |> auth(student)
        |> api_get("/api/student/courses/#{course.id}?include=chapters.lessons")
        |> json_response(200)

      assert get_in(body, ["data", "id"]) == course.id
      assert [%{"type" => "chapter"}] = included_of_type(body, "chapter")
      assert [%{"type" => "lesson"}] = included_of_type(body, "lesson")
    end

    test "does not expose an unpublished course", %{
      conn: conn,
      teacher: teacher,
      student: student
    } do
      {:ok, draft} =
        Course
        |> Ash.Changeset.for_action(:create_course, %{
          title: "草稿课 #{System.unique_integer([:positive])}",
          teacher_id: teacher.id
        })
        |> Ash.create(actor: teacher, tenant: @tenant)

      conn =
        conn
        |> auth(student)
        |> api_get("/api/student/courses/#{draft.id}")

      refute conn.status == 200
      assert %{"errors" => [_ | _]} = json_response(conn, conn.status)
    end
  end

  # ─── helpers ─────────────────────────────────────────────────────

  defp uniq, do: System.unique_integer([:positive])

  defp auth(conn, user, role \\ "student") do
    {:ok, token, _claims} =
      AuthToken.generate(user.id, %{"tenant" => @tenant, "role" => role})

    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp api_get(conn, path) do
    conn
    |> put_req_header("accept", @jsonapi)
    |> get(path)
  end

  defp api_post(conn, path, payload) do
    conn
    |> put_req_header("accept", @jsonapi)
    |> put_req_header("content-type", @jsonapi)
    |> post(path, Jason.encode!(payload))
  end

  defp included_of_type(body, type) do
    body
    |> Map.get("included", [])
    |> Enum.filter(&(&1["type"] == type))
  end

  defp create_user!(role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_action(:register_with_role, %{
        email: "ja-#{uniq()}@example.com",
        password: "password123",
        role: role
      })
      |> Ash.create(tenant: @tenant, authorize?: false)

    user
  end

  defp create_published_course!(teacher, title) do
    {:ok, course} =
      Course
      |> Ash.Changeset.for_action(:create_course, %{
        title: "#{title} #{uniq()}",
        teacher_id: teacher.id
      })
      |> Ash.create(actor: teacher, tenant: @tenant)

    {:ok, chapter} =
      Chapter
      |> Ash.Changeset.for_action(:create, %{title: "Ch1", course_id: course.id})
      |> Ash.create(tenant: @tenant, authorize?: false)

    {:ok, _lesson} =
      Lesson
      |> Ash.Changeset.for_action(:create, %{title: "L1", chapter_id: chapter.id})
      |> Ash.create(tenant: @tenant, authorize?: false)

    {:ok, published} =
      course
      |> Ash.Changeset.for_update(:publish, %{})
      |> Ash.update(actor: teacher, tenant: @tenant)

    published
  end

  defp first_lesson!(course) do
    [lesson] =
      Lesson
      |> Ash.Query.filter(chapter.course_id == ^course.id)
      |> Ash.read!(tenant: @tenant, authorize?: false)

    lesson
  end

  defp enroll!(student, course) do
    {:ok, enrollment} =
      Enrollment
      |> Ash.Changeset.for_action(:enroll, %{course_id: course.id},
        actor: student,
        tenant: @tenant
      )
      |> Ash.create()

    enrollment
  end

  defp notify!(actor, attrs) do
    attrs = attrs |> Map.new() |> Map.put_new(:type, :system)

    {:ok, notification} =
      Notification
      |> Ash.Changeset.for_action(:notify, attrs, actor: actor, tenant: @tenant)
      |> Ash.create()

    notification
  end

  defp unread_titles(user) do
    Notification
    |> Ash.Query.filter(recipient_id == ^user.id and is_nil(read_at))
    |> Ash.read!(actor: user, tenant: @tenant)
    |> Enum.map(& &1.title)
    |> Enum.sort()
  end

  defp create_exam!(teacher, name) do
    Exam
    |> Ash.Changeset.for_action(
      :create,
      %{
        name: "#{name} #{uniq()}",
        subject: :traditional_chinese_medicine,
        duration_minutes: 60
      },
      actor: teacher,
      tenant: @tenant
    )
    |> Ash.create()
  end

  defp publish!(exam, teacher) do
    exam
    |> Ash.Changeset.for_update(:publish, %{}, actor: teacher, tenant: @tenant)
    |> Ash.update()
  end
end
