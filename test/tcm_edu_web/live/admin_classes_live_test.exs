defmodule TcmEduWeb.AdminClassesLiveTest do
  @moduledoc """
  Covers the dedicated class-management page at `/admin/classes` (PhoenixTest):

    * classes can be created, renamed and deleted from the page,
    * the student count per class is shown,
    * deleting a class detaches its students (置为未分班).
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Classes.ClassGroup

  @tenant "tenant_default"

  setup %{conn: conn} do
    admin = create_user(:tenant_admin, "cls-admin")

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

  test "creates a class", %{conn: conn} do
    name = "2024 级临床 #{System.unique_integer([:positive])} 班"

    conn
    |> visit("/admin/classes")
    |> assert_has("#create-class-form")
    |> fill_in("班级名称", with: name)
    |> click_button("#create-class-form button[type='submit']", "添加班级")
    |> assert_has("#flash-info")
    |> assert_has("input[value='#{name}']")

    assert [%ClassGroup{name: ^name}] =
             Ash.read!(ClassGroup, tenant: @tenant, authorize?: false)
  end

  test "renames a class", %{conn: conn} do
    old_name = "旧班名-#{System.unique_integer([:positive])}"
    new_name = "新班名-#{System.unique_integer([:positive])}"
    class_group = create_class(old_name)

    conn
    |> visit("/admin/classes")
    |> fill_in("#rename-class-name-#{class_group.id}", "班级名称", with: new_name)
    |> click_button("#rename-class-form-#{class_group.id} button[type='submit']", "重命名")
    |> assert_has("#flash-info")

    assert Ash.get!(ClassGroup, class_group.id, tenant: @tenant, authorize?: false).name ==
             new_name
  end

  test "shows student count and detaches students on delete", %{conn: conn} do
    class_group = create_class("一班-#{System.unique_integer([:positive])}")
    student = create_user(:student, "cls-student", class_group.id)

    conn
    |> visit("/admin/classes")
    |> assert_has("#class-group-#{class_group.id}", "1")
    |> click_button("#delete-class-#{class_group.id}", "删除")
    |> assert_has("#flash-info")

    assert Ash.get!(User, student.id, tenant: @tenant, authorize?: false).class_group_id == nil
  end

  defp create_user(role, prefix, class_group_id \\ nil) do
    User
    |> Ash.Changeset.for_create(
      :register_with_role,
      %{
        email: "#{prefix}-#{System.unique_integer([:positive])}@example.com",
        name: prefix,
        password: "password123",
        role: role,
        class_group_id: class_group_id
      },
      tenant: @tenant,
      authorize?: false
    )
    |> Ash.create!()
  end

  defp create_class(name) do
    ClassGroup
    |> Ash.Changeset.for_create(:create, %{name: name}, tenant: @tenant, authorize?: false)
    |> Ash.create!()
  end
end
