defmodule TcmEduWeb.AdminPanelTest do
  @moduledoc """
  Covers the LiveView admin panel auth flow (via the unified `/login`):

    * legacy `/admin/login` redirects to the single entrance
    * protected pages redirect to `/login` without a session
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

  defp login_params(email, password) do
    %{"login" => %{"tab" => "admin", "sub" => "super", "email" => email, "password" => password}}
  end

  describe "anonymous visitors" do
    test "legacy admin login redirects to the unified entrance", %{conn: conn} do
      conn = get(conn, ~p"/admin/login")
      assert redirected_to(conn) == ~p"/login"
    end

    test "dashboard redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin")
    end

    test "tenants page redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/tenants")
    end

    test "users page redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/users")
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

    test "unified session rejects bad credentials", %{conn: conn} do
      conn = post(conn, ~p"/session", login_params(@super_email, "wrong"))

      assert redirected_to(conn) == "/login?tab=admin&admin=super"
    end

    test "unified session accepts valid credentials and logout clears it", %{
      conn: conn
    } do
      conn = post(conn, ~p"/session", login_params(@super_email, @super_password))

      assert redirected_to(conn) == ~p"/admin"
      assert get_session(conn, "admin_role") == "super_admin"

      conn = post(recycle(conn), ~p"/logout")
      assert redirected_to(conn) == ~p"/login"

      # The session is really gone: the dashboard bounces back to login.
      conn = get(recycle(conn), ~p"/admin")
      assert redirected_to(conn) == ~p"/login"
    end
  end
end
