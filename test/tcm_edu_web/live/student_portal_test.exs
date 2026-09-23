defmodule TcmEduWeb.StudentPortalTest do
  @moduledoc """
  Covers the unified login page, the student portal public pages
  (home, catalog, detail) and the student session flow.

  There is no self-registration: the API register endpoint is closed
  (covered below) and accounts are provisioned by admins.
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

  defp create_student(_) do
    user =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: @student_email,
          name: "Portal Student",
          password: @student_password,
          role: :student
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    %{student: %{id: user.id, email: to_string(user.email), actor: user}}
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

  describe "unified login" do
    test "single entrance lists all three roles, no registration", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/login")

      assert html =~ "统一登录"
      assert html =~ "学员"
      assert html =~ "教师"
      assert html =~ "管理"
      assert html =~ "login-form"
      # Field names must nest under login[...] so the submit handler sees them.
      assert html =~ ~s(name="login[email]")
      assert html =~ ~s(name="login[password]")
      refute html =~ "免费注册"
      refute html =~ "password_confirmation"
    end

    test "tab deep-link selects the teacher form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/login?tab=teacher")

      assert html =~ "进入教师端"
    end

    test "tab deep-link selects the admin form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/login?tab=admin")

      assert html =~ "进入管理端"
      assert html =~ "超级管理员"
      assert html =~ "租户管理员"
    end

    test "invalid input shows errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      html =
        render_submit(view, "submit", %{
          "login" => %{"tab" => "student", "email" => "someone", "password" => ""}
        })

      assert html =~ "请输入密码"
    end

    test "public API registration stays closed", %{conn: conn} do
      conn =
        post(conn, ~p"/api/auth/user/password/register", %{
          "user" => %{
            "email" => "selfreg-#{System.unique_integer([:positive])}@example.com",
            "password" => "password123",
            "password_confirmation" => "password123"
          }
        })

      refute conn.status == 200
    end
  end

  describe "public pages" do
    test "home renders hero and catalog sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "系统学中医"
      assert html =~ "大家都在学"
      assert html =~ "名师风采" or html =~ "课程分类"
    end

    test "home top-right has a single login button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "登录"
      refute html =~ "免费注册"
    end

    test "courses catalog renders", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/courses")

      assert html =~ "精品课程"
    end

    test "resources downloads page renders", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/resources")

      assert html =~ "资料下载"
      assert html =~ "全部资料"
      assert html =~ "推荐题库"
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
    setup [:create_student]

    test "login accepts valid credentials", %{conn: conn, student: student} do
      conn =
        post(conn, ~p"/session", %{
          "login" => %{
            "tab" => "student",
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
        post(conn, ~p"/session", %{
          "login" => %{"tab" => "student", "email" => "nobody@example.com", "password" => "wrong"}
        })

      assert redirected_to(conn) == "/login?tab=student"
    end

    test "logout returns home as visitor", %{conn: conn, student: student} do
      authed = student_session(conn, student)

      conn = post(authed, ~p"/logout")
      assert redirected_to(conn) == ~p"/login"

      {:ok, _view, html} = live(recycle(conn), ~p"/")
      assert html =~ "登录"
    end
  end
end
