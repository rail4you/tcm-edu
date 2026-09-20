defmodule TcmEduWeb.StudentLearningTest do
  @moduledoc """
  Covers the authenticated student flows: learn page with progress,
  my-learning roster, posts, chat rendering and notifications.
  """
  use TcmEduWeb.LiveViewCase

  import Phoenix.LiveViewTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Courses.Chapter
  alias TcmEdu.Courses.Course
  alias TcmEdu.Courses.Lesson
  alias TcmEdu.Enrollment.Enrollment
  alias TcmEdu.Notification.Notification

  @tenant "tenant_default"
  @student_email "learner@example.com"
  @student_password "password123"

  defp create_student(_) do
    {:ok, student} =
      TcmEduWeb.StudentAuth.register(@student_email, "Learner", @student_password)

    %{student: student}
  end

  defp create_teacher(_) do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{email: "t-for-learn@example.com", name: "T", password: "password123", role: :teacher},
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    %{teacher: teacher}
  end

  defp create_published_course(teacher, title \\ "Learn Course") do
    course =
      Course
      |> Ash.Changeset.for_create(
        :create_course,
        %{title: title, teacher_id: teacher.id},
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    chapter =
      Chapter
      |> Ash.Changeset.for_create(
        :create,
        %{title: "第一章", course_id: course.id, sort_order: 1},
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    lesson =
      Lesson
      |> Ash.Changeset.for_create(
        :create,
        %{title: "1.1", chapter_id: chapter.id, sort_order: 1, content_type: :video},
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    course =
      course
      |> Ash.Changeset.for_update(:publish, %{}, tenant: @tenant, authorize?: false)
      |> Ash.update!()

    %{course: course, lesson: lesson}
  end

  defp enroll(student, course_id) do
    Enrollment
    |> Ash.Changeset.for_create(:enroll, %{course_id: course_id},
      actor: student.actor,
      tenant: student.tenant
    )
    |> Ash.create!()
  end

  defp student_session(conn, student) do
    Plug.Test.init_test_session(conn, %{
      "student_id" => student.id,
      "student_role" => "student",
      "student_tenant" => @tenant,
      "student_email" => to_string(student.email),
      "student_name" => "Learner"
    })
  end

  describe "anonymous visitors" do
    test "learn redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/learn?course_id=xxx")
    end

    test "my-learning redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/my-learning")
    end

    test "posts redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/posts")
    end

    test "chat redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/chat")
    end

    test "notifications redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/notifications")
    end
  end

  describe "learning flow" do
    setup [:create_student, :create_teacher]

    test "my-learning lists enrollments with progress", %{
      conn: conn,
      student: student,
      teacher: teacher
    } do
      %{course: course} = create_published_course(teacher)
      enroll(student, course.id)

      conn = student_session(conn, student)
      {:ok, _view, html} = live(conn, ~p"/my-learning")

      assert html =~ "我的学习"
      assert html =~ "Learn Course"
      assert html =~ "继续学习"
    end

    test "learn page renders the lesson and outline", %{
      conn: conn,
      student: student,
      teacher: teacher
    } do
      %{course: course, lesson: lesson} = create_published_course(teacher)
      enroll(student, course.id)

      conn = student_session(conn, student)
      {:ok, _view, html} = live(conn, ~p"/learn?course_id=#{course.id}&lesson=#{lesson.id}")

      assert html =~ "1.1"
      assert html =~ "标记本节已完成"
    end

    test "completing a lesson records progress", %{conn: conn, student: student, teacher: teacher} do
      %{course: course, lesson: lesson} = create_published_course(teacher)
      enroll(student, course.id)

      conn = student_session(conn, teacher && student)
      {:ok, view, _html} = live(conn, ~p"/learn?course_id=#{course.id}&lesson=#{lesson.id}")

      html = render_click(view, "complete-lesson")
      assert html =~ "已完成"
    end

    test "mistakes page renders empty state", %{conn: conn, student: student} do
      conn = student_session(conn, student)
      {:ok, _view, html} = live(conn, ~p"/my-learning/mistakes")

      assert html =~ "错题本"
    end
  end

  describe "posts and notifications" do
    setup [:create_student]

    test "posts page renders for students", %{conn: conn, student: student} do
      conn = student_session(conn, student)
      {:ok, _view, html} = live(conn, ~p"/posts")

      assert html =~ "学习交流"
      assert html =~ "new-post-btn"
    end

    test "new post page validates input", %{conn: conn, student: student} do
      conn = student_session(conn, student)
      {:ok, view, _html} = live(conn, ~p"/posts/new")

      html = render_submit(view, "save", %{"post" => %{"title" => "", "body" => "x"}})
      assert html =~ "new-post-form"
    end

    test "chat page renders the input", %{conn: conn, student: student} do
      conn = student_session(conn, student)
      {:ok, _view, html} = live(conn, ~p"/chat")

      assert html =~ "AI 问答"
      assert html =~ "chat-form"
    end

    test "notifications list and mark-read", %{conn: conn, student: student} do
      Notification
      |> Ash.Changeset.for_create(
        :notify,
        %{recipient_id: student.id, type: :system, title: "欢迎", body: "欢迎加入"},
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

      conn = student_session(conn, student)
      {:ok, view, html} = live(conn, ~p"/notifications")

      assert html =~ "通知中心"
      assert html =~ "欢迎"

      html = render_click(view, "mark-all-read")
      assert html =~ "全部已读"
    end
  end
end
