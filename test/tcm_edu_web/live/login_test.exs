defmodule TcmEduWeb.LoginTest do
  @moduledoc """
  Covers the unified login page (`/login`, PhoenixTest + LiveViewTest):

    * tenant users pick their organization; super admin login stays
      tab-isolated with no tenant selector
    * failed submits keep tab/tenant/email/password and show an inline
      error instead of resetting the page
    * missing tenant blocks submit with an inline error
    * the session controller passes tenant through and preserves tab/sub
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

  test "tenant selector lists organizations on tenant tabs, hidden for super", %{
    conn: conn,
    org: org
  } do
    conn
    |> visit("/login")
    |> assert_has("#login-form select[name='login[tenant]']")
    |> assert_has("#login-form option", text: org.name)
    |> visit("/login?tab=teacher")
    |> assert_has("#login-form select[name='login[tenant]']")
    |> visit("/login?tab=admin")
    |> refute_has("#login-form select[name='login[tenant]']")
    |> click_button("租户管理员")
    |> assert_has("#login-form select[name='login[tenant]']")
  end

  test "failed submit keeps state and shows an inline error", %{conn: conn, org: org} do
    {:ok, view, _html} = live(conn, "/login?tab=student")

    email = "login-state-#{System.unique_integer([:positive])}@example.com"

    html =
      render_submit(view, "submit", %{
        "login" => %{
          "tab" => "student",
          "tenant" => org.schema_name,
          "email" => email,
          "password" => "wrong-password"
        }
      })

    assert html =~ "账号或密码错误"
    # Tab, tenant, email and password are all preserved (no reset).
    assert html =~ "登录学习"
    assert html =~ ~s(value="#{org.schema_name}")
    assert html =~ ~s(value="#{email}")
    assert html =~ ~s(value="wrong-password")
  end

  test "missing tenant blocks submit with an inline error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/login?tab=teacher")

    html =
      render_submit(view, "submit", %{
        "login" => %{
          "tab" => "teacher",
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
          "tab" => "student",
          "tenant" => org.schema_name,
          "email" => to_string(student.email),
          "password" => @password
        }
      })

    assert redirected_to(conn) == "/my-learning"
    assert get_session(conn, "student_tenant") == org.schema_name
  end

  test "student can log in with username instead of email", %{
    conn: conn,
    org: org,
    student: student
  } do
    conn =
      post(conn, "/session", %{
        "login" => %{
          "tab" => "student",
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
          "tab" => "teacher",
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
          "tab" => "student",
          "tenant" => org.schema_name,
          "email" => student.name,
          "password" => "wrong-password"
        }
      })

    assert redirected_to(conn) == "/login?tab=student"
    assert get_session(conn, "student_id") == nil
  end

  test "session controller preserves tab/sub when denying", %{conn: conn} do
    conn =
      post(conn, "/session", %{
        "login" => %{"tab" => "teacher", "email" => "nobody@example.com", "password" => "wrong"}
      })

    assert redirected_to(conn) == "/login?tab=teacher"

    conn =
      post(recycle(conn), "/session", %{
        "login" => %{
          "tab" => "admin",
          "sub" => "tenant",
          "email" => "nobody@example.com",
          "password" => "wrong"
        }
      })

    assert redirected_to(conn) == "/login?tab=admin&admin=tenant"
  end

  test "password toggle markup is present", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/login")

    assert html =~ "PasswordToggle"
    assert html =~ "data-pw-toggle"
    assert html =~ "显示密码"
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
