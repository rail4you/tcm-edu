defmodule TcmEduWeb.AdminAccountLiveTest do
  @moduledoc """
  Covers the admin account page at `/admin/account` (PhoenixTest):

    * a tenant admin sees their profile info and both forms,
    * profile edits are persisted,
    * a wrong current password is rejected inline,
    * a valid password change takes effect immediately.
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.System.SuperAdmin

  @tenant "tenant_default"
  @old_password "password123"
  @new_password "newpass456"

  setup %{conn: conn} do
    admin =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "acct-admin-#{System.unique_integer([:positive])}@example.com",
          name: "Acct Admin",
          password: @old_password,
          role: :tenant_admin
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "admin_id" => admin.id,
        "admin_role" => "tenant_admin",
        "admin_tenant" => @tenant,
        "admin_email" => to_string(admin.email),
        "admin_name" => admin.name
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, admin: admin}
  end

  test "shows profile info and both forms", %{conn: conn, admin: admin} do
    conn
    |> visit("/admin/account")
    |> assert_has("#profile-form")
    |> assert_has("#password-form")
    |> assert_has("p", to_string(admin.email))
    |> assert_has("span", "租户管理员")
  end

  test "uploads own avatar", %{conn: conn, admin: admin} do
    tmp_dir = Path.join(System.tmp_dir!(), "acct-avatar-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    path = Path.join(tmp_dir, "avatar.png")
    File.write!(path, <<137, 80, 78, 71, 13, 10, 26, 10>>)

    conn
    |> visit("/admin/account")
    |> upload("选择图片", path, exact: false)
    |> click_button("#profile-form button[type='submit']", "保存资料")
    |> assert_has("#flash-info")

    loaded =
      User
      |> Ash.get!(admin.id, tenant: @tenant, authorize?: false)
      |> Ash.load!(:avatar_url, tenant: @tenant, authorize?: false)

    assert loaded.avatar_url
  end

  test "updates the profile", %{conn: conn, admin: admin} do
    conn
    |> visit("/admin/account")
    |> fill_in("姓名", with: "新名字")
    |> click_button("#profile-form button[type='submit']", "保存资料")
    |> assert_has("#flash-info")
    |> assert_has("p", "新名字")

    assert Ash.get!(User, admin.id, tenant: @tenant, authorize?: false).full_name == "新名字"
  end

  test "rejects a wrong current password", %{conn: conn} do
    conn
    |> visit("/admin/account")
    |> fill_in("当前密码", with: "wrongpass")
    |> fill_in("新密码", with: @new_password)
    |> fill_in("确认新密码", with: @new_password)
    |> click_button("#password-form button[type='submit']", "保存密码")
    |> assert_has("#password-form", "当前密码不正确")
  end

  test "changes the password", %{conn: conn, admin: admin} do
    conn
    |> visit("/admin/account")
    |> fill_in("当前密码", with: @old_password)
    |> fill_in("新密码", with: @new_password)
    |> fill_in("确认新密码", with: @new_password)
    |> click_button("#password-form button[type='submit']", "保存密码")
    |> assert_has("#flash-info")

    assert {:ok, _} =
             TcmEduWeb.AdminAuth.authenticate(
               to_string(admin.email),
               @new_password,
               "tenant",
               @tenant
             )
  end

  test "super admin can view and update their profile" do
    super =
      SuperAdmin
      |> Ash.Changeset.for_create(
        :register,
        %{
          email: "acct-super-#{System.unique_integer([:positive])}@example.com",
          name: "Super Admin",
          password: @old_password
        },
        authorize?: false
      )
      |> Ash.create!()

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{
        "admin_id" => super.id,
        "admin_role" => "super_admin",
        "admin_tenant" => "public",
        "admin_email" => to_string(super.email),
        "admin_name" => super.name
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    conn
    |> visit("/admin/account")
    |> assert_has("#profile-form")
    |> assert_has("span", "超级管理员")
    |> fill_in("姓名", with: "超管新名")
    |> click_button("#profile-form button[type='submit']", "保存资料")
    |> assert_has("#flash-info")

    assert Ash.get!(SuperAdmin, super.id, authorize?: false).name == "超管新名"
  end
end
