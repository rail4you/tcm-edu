defmodule TcmEduWeb.LoginTest do
  @moduledoc """
  Covers the unified login page (`/login`, PhoenixTest + LiveViewTest):

    * tenant mode (default): organization selector on top, then role
      buttons (学员 / 教师 / 租户管理)
    * super-admin mode (bottom link): no tenant selector
    * failed submits keep tenant/identity/password and show an inline
      error instead of resetting the page
    * missing tenant blocks submit with an inline error
    * the session controller passes tenant through and preserves mode/role
      when redirecting back on failure
    * password visibility toggle markup is present
  """

  use TcmEduWeb.LiveViewCase

  import Phoenix.LiveViewTest
  import PhoenixTest

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Repo
  alias TcmEdu.System.Organization

  @password "password123"

  setup %{conn: conn} do
    org = create_org!("login-org")

    student =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "login-student-#{System.unique_integer([:positive])}@example.com",
          name: "Login Student",
          password: @password,
          role: :student
        },
        tenant: org.schema_name,
        authorize?: false
      )
      |> Ash.create!()

    conn = PhoenixTest.put_endpoint(conn, TcmEduWeb.Endpoint)

    {:ok, conn: conn, org: org, student: student}
  end

  test "tenant mode shows org selector first, then role buttons", %{conn: conn, org: org} do
    conn
    |> visit("/login")
    |> assert_has("#tenant-select")
    |> assert_has("#tenant-select option", text: org.name)
    |> assert_has("button", text: "学员")
    |> assert_has("button", text: "教师")
    |> assert_has("button", text: "租户管理")
    |> assert_has("#super-login-link", "超级管理员登录")
    |> assert_has("button", text: "登录学习")
  end

  test "switching role updates the submit button and URL", %{conn: conn} do
    conn
    |> visit("/login")
    |> click_button("教师")
    |> assert_has("button", text: "进入教师端")
    |> click_button("租户管理")
    |> assert_has("button", text: "进入管理端")

    {:ok, _view, html} = live(conn, "/login?role=teacher")
    assert html =~ "进入教师端"
  end

  test "super-admin mode has no tenant selector", %{conn: conn} do
    conn
    |> visit("/login")
    |> click_button("超级管理员登录")
    |> refute_has("#tenant-select")
    |> assert_has("button", text: "进入管理端")
    |> assert_has("#tenant-login-link", "返回租户登录")

    {:ok, _view, html} = live(conn, "/login?mode=super")
    assert html =~ "超级管理员登录"
    refute html =~ "tenant-select"
  end

  test "legacy tab params still map onto the new UI", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/login?tab=teacher")
    assert html =~ "进入教师端"

    {:ok, _view, html} = live(conn, "/login?tab=admin&admin=tenant")
    assert html =~ "进入管理端"
    assert html =~ "tenant-select"

    {:ok, _view, html} = live(conn, "/login?tab=admin")
    assert html =~ "超级管理员登录"
    refute html =~ "tenant-select"
  end

  test "failed submit keeps state and shows an inline error", %{conn: conn, org: org} do
    {:ok, view, _html} = live(conn, "/login")

    email = "login-state-#{System.unique_integer([:positive])}@example.com"

    html =
      render_submit(view, "submit", %{
        "login" => %{
          "mode" => "tenant",
          "role" => "student",
          "tenant" => org.schema_name,
          "email" => email,
          "password" => "wrong-password"
        }
      })

    assert html =~ "账号或密码错误"
    # Tenant, identity and password are all preserved (no reset).
    assert html =~ "登录学习"
    assert html =~ ~s(value="#{org.schema_name}")
    assert html =~ ~s(value="#{email}")
    assert html =~ ~s(value="wrong-password")
  end

  test "missing tenant blocks submit with an inline error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/login?role=teacher")

    html =
      render_submit(view, "submit", %{
        "login" => %{
          "mode" => "tenant",
          "role" => "teacher",
          "tenant" => "",
          "email" => "teacher@example.com",
          "password" => @password
        }
      })

    assert html =~ "请选择所属机构"
  end

  test "session controller passes tenant through on success", %{
    conn: conn,
    org: org,
    student: student
  } do
    conn =
      post(conn, "/session", %{
        "login" => %{
          "mode" => "tenant",
          "role" => "student",
          "tenant" => org.schema_name,
          "email" => to_string(student.email),
          "password" => @password
        }
      })

    assert redirected_to(conn) == "/my-learning"
    assert get_session(conn, "student_tenant") == org.schema_name
  end

  test "tenant admin can log in with email", %{conn: conn, org: org} do
    email = "login-admin-#{System.unique_integer([:positive])}@example.com"

    User
    |> Ash.Changeset.for_create(
      :register_with_role,
      %{email: email, name: "Login Admin", password: @password, role: :tenant_admin},
      tenant: org.schema_name,
      authorize?: false
    )
    |> Ash.create!()

    conn =
      post(conn, "/session", %{
        "login" => %{
          "mode" => "tenant",
          "role" => "tenant_admin",
          "tenant" => org.schema_name,
          "email" => email,
          "password" => @password
        }
      })

    assert redirected_to(conn) == "/admin"
  end

  test "session controller preserves mode/role when denying", %{conn: conn} do
    conn =
      post(conn, "/session", %{
        "login" => %{
          "mode" => "tenant",
          "role" => "teacher",
          "email" => "nobody@example.com",
          "password" => "wrong"
        }
      })

    assert redirected_to(conn) == "/login?role=teacher"

    conn =
      post(recycle(conn), "/session", %{
        "login" => %{"mode" => "super", "email" => "nobody@example.com", "password" => "wrong"}
      })

    assert redirected_to(conn) == "/login?mode=super"
  end

  test "legacy tab params still log in via the session controller", %{
    conn: conn,
    org: org,
    student: student
  } do
    conn =
      post(conn, "/session", %{
        "login" => %{
          "tab" => "student",
          "tenant" => org.schema_name,
          "email" => to_string(student.email),
          "password" => @password
        }
      })

    assert redirected_to(conn) == "/my-learning"
  end

  test "student can log in with username instead of email", %{
    conn: conn,
    org: org,
    student: student
  } do
    conn =
      post(conn, "/session", %{
        "login" => %{
          "mode" => "tenant",
          "role" => "student",
          "tenant" => org.schema_name,
          "email" => student.name,
          "password" => @password
        }
      })

    assert redirected_to(conn) == "/my-learning"
    assert get_session(conn, "student_id") == student.id
  end

  test "teacher can log in with username instead of email", %{conn: conn, org: org} do
    name = "Login Teacher #{System.unique_integer([:positive])}"

    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "login-teacher-#{System.unique_integer([:positive])}@example.com",
          name: name,
          password: @password,
          role: :teacher
        },
        tenant: org.schema_name,
        authorize?: false
      )
      |> Ash.create!()

    conn =
      post(conn, "/session", %{
        "login" => %{
          "mode" => "tenant",
          "role" => "teacher",
          "tenant" => org.schema_name,
          "email" => name,
          "password" => @password
        }
      })

    assert redirected_to(conn) == "/teacher"
    assert get_session(conn, "teacher_id") == teacher.id
  end

  test "username with wrong password is denied", %{conn: conn, org: org, student: student} do
    conn =
      post(conn, "/session", %{
        "login" => %{
          "mode" => "tenant",
          "role" => "student",
          "tenant" => org.schema_name,
          "email" => student.name,
          "password" => "wrong-password"
        }
      })

    assert redirected_to(conn) == "/login"
    assert get_session(conn, "student_id") == nil
  end

  test "password visibility can be toggled", %{conn: conn} do
    {:ok, view, html} = live(conn, "/login")

    assert html =~ ~s(phx-click="toggle-password")
    assert html =~ "显示密码"
    assert has_element?(view, "input#login-password-input[type='password']")

    view |> element("button[aria-label='显示密码']") |> render_click()

    assert has_element?(view, "input#login-password-input[type='text']")
    assert has_element?(view, "button[aria-label='隐藏密码']")
  end

  test "visiting /logout with GET also signs out", %{conn: conn} do
    conn = get(conn, "/logout")

    assert redirected_to(conn) == "/login"
  end

  defp create_org!(slug_root) do
    slug = "#{slug_root}-#{System.unique_integer([:positive])}"
    org = Ash.create!(Organization, %{name: "机构 #{slug}", slug: slug}, authorize?: false)
    register_org_cleanup(org)
    org
  end

  defp register_org_cleanup(%Organization{} = org) do
    on_exit(fn ->
      try do
        if schema_exists?(org.schema_name) do
          Repo.query("DROP SCHEMA IF EXISTS \"#{org.schema_name}\" CASCADE")
        end
      rescue
        _ -> :ok
      end
    end)
  end

  defp schema_exists?(name) do
    case Repo.query("SELECT 1 FROM pg_namespace WHERE nspname = $1", [name]) do
      {:ok, %{rows: [[1]]}} -> true
      _ -> false
    end
  end
end
