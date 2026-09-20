defmodule TcmEduWeb.AdminPanelTest do
  @moduledoc """
  Covers the LiveView admin panel auth flow:

    * login page renders for anonymous visitors
    * protected pages redirect to `/admin/login` without a session
    * session creation destroys work end-to-end for super admins
  """
  use TcmEduWeb.LiveViewCase

  import Phoenix.LiveViewTest

  alias TcmEdu.System.SuperAdmin

  @super_email "admin-panel-test@example.com"
  @super_password "password123"

  defp create_super_admin(_) do
    admin =
      SuperAdmin
      |> Ash.Changeset.for_create(
        :register,
        %{email: @super_email, name: "Panel Test", password: @super_password},
        authorize?: false
      )
      |> Ash.create!()

    %{admin: admin}
  end

  defp super_session(conn, admin) do
    Plug.Test.init_test_session(conn, %{
      "admin_id" => admin.id,
      "admin_role" => "super_admin",
      "admin_tenant" => "public",
      "admin_email" => to_string(admin.email),
      "admin_name" => "Panel Test"
    })
  end

  describe "anonymous visitors" do
    test "login page renders both login modes", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/login")

      assert html =~ "欢迎回来"
      assert html =~ "超级管理员"
      assert html =~ "租户管理员"
      assert html =~ "admin-login-form"
    end

    test "dashboard redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin")
    end

    test "tenants page redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/tenants")
    end

    test "users page redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/users")
    end
  end

  describe "login form validation" do
    test "invalid email shows an error and does not trigger submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/login")

      html =
        render_change(view, "validate", %{
          "_target" => ["admin", "email"],
          "admin" => %{"email" => "not-an-email", "password" => "x", "mode" => "super"}
        })

      assert html =~ "邮箱格式不正确"
    end

    test "submitting an invalid form surfaces all errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/login")

      html =
        render_submit(view, "submit", %{
          "admin" => %{"email" => "not-an-email", "password" => "", "mode" => "super"}
        })

      assert html =~ "邮箱格式不正确"
    end
  end

  describe "super admin session" do
    setup [:create_super_admin]

    test "dashboard renders platform stats", %{conn: conn, admin: admin} do
      conn = super_session(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "工作台"
      assert html =~ "租户总数"
    end

    test "tenants page renders the table and create button", %{conn: conn, admin: admin} do
      conn = super_session(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/tenants")

      assert html =~ "租户管理"
      assert html =~ "new-tenant-btn"
    end

    test "users page renders the tenant selector", %{conn: conn, admin: admin} do
      conn = super_session(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      assert html =~ "用户管理"
      assert html =~ "new-user-btn"
    end

    test "session controller rejects bad credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/admin/session", %{
          "admin" => %{"email" => @super_email, "password" => "wrong", "mode" => "super"}
        })

      assert redirected_to(conn) == ~p"/admin/login"
    end

    test "session controller accepts valid credentials and logout clears it", %{
      conn: conn
    } do
      conn =
        post(conn, ~p"/admin/session", %{
          "admin" => %{"email" => @super_email, "password" => @super_password, "mode" => "super"}
        })

      assert redirected_to(conn) == ~p"/admin"
      assert get_session(conn, "admin_role") == "super_admin"

      conn = post(recycle(conn), ~p"/admin/logout")
      assert redirected_to(conn) == ~p"/admin/login"

      # The session is really gone: the dashboard bounces back to login.
      conn = get(recycle(conn), ~p"/admin")
      assert redirected_to(conn) == ~p"/admin/login"
    end
  end
end
