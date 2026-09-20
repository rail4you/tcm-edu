defmodule TcmEduWeb.StudentPortalTest do
  @moduledoc """
  Covers the student portal public pages (home, login, catalog, detail)
  and the session login/registration flow.
  """
  use TcmEduWeb.LiveViewCase

  import Phoenix.LiveViewTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Courses.Chapter
  alias TcmEdu.Courses.Course
  alias TcmEdu.Courses.Lesson

  @tenant "tenant_default"
  @student_email "student-portal-test@example.com"
  @student_password "password123"

  defp create_teacher(_) do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "teacher-for-course@example.com",
          name: "T",
          password: "password123",
          role: :teacher
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    %{teacher: teacher}
  end

  defp create_published_course(teacher, title \\ " published course") do
    course =
      Course
      |> Ash.Changeset.for_create(
        :create_course,
        %{title: String.trim(title), teacher_id: teacher.id},
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

    Lesson
    |> Ash.Changeset.for_create(
      :create,
      %{title: "1.1", chapter_id: chapter.id, sort_order: 1, content_type: :video},
      tenant: @tenant,
      authorize?: false
    )
    |> Ash.create!()

    course
    |> Ash.Changeset.for_update(:publish, %{}, tenant: @tenant, authorize?: false)
    |> Ash.update!()
  end

  defp student_session(conn, student) do
    Plug.Test.init_test_session(conn, %{
      "student_id" => student.id,
      "student_role" => "student",
      "student_tenant" => @tenant,
      "student_email" => to_string(student.email),
      "student_name" => "Portal Student"
    })
  end

  describe "public pages" do
    test "home renders hero and catalog sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "系统学中医"
      assert html =~ "大家都在学"
      assert html =~ "名师风采" or html =~ "课程分类"
    end

    test "login page renders both tabs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/login")

      assert html =~ "student-login-form"
      assert html =~ "免费注册"
    end

    test "register tab renders via query param", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/login?mode=register")

      assert html =~ "student-register-form"
    end

    test "invalid login input shows errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      html =
        render_submit(view, "submit-login", %{
          "student" => %{"email" => "bad", "password" => ""}
        })

      assert html =~ "邮箱格式不正确"
    end

    test "courses catalog renders", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/courses")

      assert html =~ "课程表"
    end
  end

  describe "course detail" do
    setup [:create_teacher]

    test "published course renders for visitors", %{conn: conn, teacher: teacher} do
      course = create_published_course(teacher, "经络腧穴学")
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}")

      assert html =~ "经络腧穴学"
      assert html =~ "课程大纲"
      assert html =~ "enroll-btn"
    end

    test "anonymous enroll click goes to login", %{conn: conn, teacher: teacher} do
      course = create_published_course(teacher)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}")

      assert {:error, {:live_redirect, %{to: "/login"}}} = render_click(view, "enroll")
    end
  end

  describe "student session" do
    test "registration creates the account and logs in", %{conn: conn} do
      conn =
        post(conn, ~p"/student/session", %{
          "student" => %{
            "mode" => "register",
            "email" => @student_email,
            "name" => "Portal Student",
            "password" => @student_password,
            "password_confirmation" => @student_password
          }
        })

      assert redirected_to(conn) == ~p"/my-learning"
      assert get_session(conn, "student_role") == "student"
    end

    test "login accepts valid credentials", %{conn: conn} do
      {:ok, student} =
        TcmEduWeb.StudentAuth.register(@student_email, "Portal Student", @student_password)

      conn =
        post(conn, ~p"/student/session", %{
          "student" => %{
            "mode" => "login",
            "email" => @student_email,
            "password" => @student_password
          }
        })

      assert redirected_to(conn) == ~p"/my-learning"
      assert get_session(conn, "student_id") == student.id

      authed = student_session(recycle(conn), student)
      {:ok, _view, html} = live(authed, ~p"/")

      assert html =~ "继续学习"
    end

    test "login rejects bad credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/student/session", %{
          "student" => %{
            "mode" => "login",
            "email" => "nobody@example.com",
            "password" => "wrong"
          }
        })

      assert redirected_to(conn) == ~p"/login"
    end

    test "logout returns home as visitor", %{conn: conn} do
      {:ok, student} =
        TcmEduWeb.StudentAuth.register(@student_email, "Portal Student", @student_password)

      authed = student_session(conn, student)

      conn = post(authed, ~p"/student/logout")
      assert redirected_to(conn) == ~p"/"

      {:ok, _view, html} = live(recycle(conn), ~p"/")
      assert html =~ "免费注册"
    end
  end
end
