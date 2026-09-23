defmodule TcmEduWeb.AdminUsersPasswordTest do
  @moduledoc """
  Covers super-admin password reset at `/admin/users` (PhoenixTest):

    * the row-level "重置密码" button opens a modal for the right user,
    * mismatched confirmation is rejected inline,
    * a valid reset takes effect: the old password stops working and the
      new one authenticates.
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
      SuperAdmin
      |> Ash.Changeset.for_create(
        :register,
        %{
          email: "pw-admin-#{System.unique_integer([:positive])}@example.com",
          name: "Pw Admin",
          password: "password123"
        },
        authorize?: false
      )
      |> Ash.create!()

    student =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "pw-student-#{System.unique_integer([:positive])}@example.com",
          name: "Pw Student #{System.unique_integer([:positive])}",
          password: @old_password,
          role: :student
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "admin_id" => admin.id,
        "admin_role" => "super_admin",
        "admin_tenant" => "public",
        "admin_email" => to_string(admin.email),
        "admin_name" => "Pw Admin"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, student: student}
  end

  test "reset button opens the modal for the right user", %{conn: conn, student: student} do
    conn
    |> visit("/admin/users")
    |> click_button("#reset-password-#{student.id}", "重置密码")
    |> assert_has("#reset-password-form")
    |> assert_has("p", to_string(student.email))
  end

  test "mismatched confirmation is rejected", %{conn: conn, student: student} do
    conn
    |> visit("/admin/users")
    |> click_button("#reset-password-#{student.id}", "重置密码")
    |> fill_in("新密码", with: @new_password)
    |> fill_in("确认新密码", with: "different777")
    |> click_button("#reset-password-form button[type='submit']", "保存新密码")
    |> assert_has("#reset-password-form", "两次输入不一致")

    assert {:error, :invalid_credentials} =
             TcmEduWeb.StudentAuth.authenticate(
               to_string(student.email),
               @new_password,
               @tenant
             )
  end

  test "valid reset takes effect immediately", %{conn: conn, student: student} do
    conn
    |> visit("/admin/users")
    |> click_button("#reset-password-#{student.id}", "重置密码")
    |> fill_in("新密码", with: @new_password)
    |> fill_in("确认新密码", with: @new_password)
    |> click_button("#reset-password-form button[type='submit']", "保存新密码")
    |> assert_has("p", "已重置")
    # Flash auto-dismisses via the hook instead of lingering until clicked.
    |> assert_has("#flash-info[data-flash-ttl='2000']")

    assert {:error, :invalid_credentials} =
             TcmEduWeb.StudentAuth.authenticate(
               to_string(student.email),
               @old_password,
               @tenant
             )

    assert {:ok, _} =
             TcmEduWeb.StudentAuth.authenticate(
               to_string(student.email),
               @new_password,
               @tenant
             )
  end
end
