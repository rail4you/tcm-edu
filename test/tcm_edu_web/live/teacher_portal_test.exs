defmodule TcmEduWeb.TeacherPortalTest do
  @moduledoc """
  Covers the LiveView teacher portal: login rendering, auth redirects,
  session login/logout, and the core teaching pages.
  """
  use TcmEduWeb.LiveViewCase

  import Phoenix.LiveViewTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Courses.Course

  @tenant "tenant_default"
  @teacher_email "teacher-portal-test@example.com"
  @teacher_password "password123"

  defp create_teacher(_) do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: @teacher_email,
          name: "Portal Teacher",
          password: @teacher_password,
          role: :teacher
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    %{teacher: teacher}
  end

  defp teacher_session(conn, teacher) do
    Plug.Test.init_test_session(conn, %{
      "teacher_id" => teacher.id,
      "teacher_role" => "teacher",
      "teacher_tenant" => @tenant,
      "teacher_email" => to_string(teacher.email),
      "teacher_name" => "Portal Teacher"
    })
  end

  defp create_course(teacher, title \\ "测试课程") do
    Course
    |> Ash.Changeset.for_create(
      :create_course,
      %{title: title, teacher_id: teacher.id},
      tenant: @tenant,
      authorize?: false
    )
    |> Ash.create!()
  end

  describe "anonymous visitors" do
    test "legacy teacher login redirects to the unified entrance", %{conn: conn} do
      conn = get(conn, ~p"/teacher/login")
      assert redirected_to(conn) == ~p"/login"
    end

    test "dashboard redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/teacher")
    end

    test "courses page redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/teacher/courses")
    end

    test "students page redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/teacher/students")
    end
  end

  describe "teacher session" do
    setup [:create_teacher]

    test "dashboard renders course stats", %{conn: conn, teacher: teacher} do
      create_course(teacher)
      conn = teacher_session(conn, teacher)
      {:ok, _view, html} = live(conn, ~p"/teacher")

      assert html =~ "工作台"
      assert html =~ "全部课程"
    end

    test "courses page renders with new-course button", %{conn: conn, teacher: teacher} do
      conn = teacher_session(conn, teacher)
      {:ok, _view, html} = live(conn, ~p"/teacher/courses")

      assert html =~ "我的课程"
      assert html =~ "new-course-btn"
    end

    test "new course page renders the form", %{conn: conn, teacher: teacher} do
      conn = teacher_session(conn, teacher)
      {:ok, _view, html} = live(conn, ~p"/teacher/courses/new")

      assert html =~ "创建课程"
      assert html =~ "new-course-form"
    end

    test "creating a course navigates back to the list", %{conn: conn, teacher: teacher} do
      conn = teacher_session(conn, teacher)
      {:ok, view, _html} = live(conn, ~p"/teacher/courses/new")

      assert {:error, {:live_redirect, %{to: to}}} =
               render_submit(view, "save", %{
                 "course" => %{"title" => "经络腧穴学", "level" => "beginner", "price_yuan" => "0"}
               })

      assert to == "/teacher/courses"
    end

    test "students page renders the roster", %{conn: conn, teacher: teacher} do
      conn = teacher_session(conn, teacher)
      {:ok, _view, html} = live(conn, ~p"/teacher/students")

      assert html =~ "我的学生"
    end

    test "unified session accepts valid credentials and logout clears it", %{
      conn: conn
    } do
      conn =
        post(conn, ~p"/session", %{
          "login" => %{
            "tab" => "teacher",
            "email" => @teacher_email,
            "password" => @teacher_password
          }
        })

      assert redirected_to(conn) == ~p"/teacher"
      assert get_session(conn, "teacher_role") == "teacher"

      conn = post(recycle(conn), ~p"/logout")
      assert redirected_to(conn) == ~p"/login"

      conn = get(recycle(conn), ~p"/teacher")
      assert redirected_to(conn) == ~p"/login"
    end

    test "unified session rejects bad credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/session", %{
          "login" => %{"tab" => "teacher", "email" => @teacher_email, "password" => "wrong"}
        })

      assert redirected_to(conn) == "/login?role=teacher"
    end
  end
end
