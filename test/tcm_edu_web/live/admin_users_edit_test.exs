defmodule TcmEduWeb.AdminUsersEditTest do
  @moduledoc """
  Covers admin user editing + class assignment at `/admin/users` (PhoenixTest):

    * the row "编辑" button opens a role-aware edit modal,
    * student fields (学号/专业/班级) are editable and persisted,
    * the class filter narrows the list to one class.
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Classes.ClassGroup

  @tenant "tenant_default"

  setup %{conn: conn} do
    admin = create_user(:tenant_admin, "edit-admin")
    teacher = create_user(:teacher, "edit-teacher")
    student = create_user(:student, "edit-student")

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

    {:ok, conn: conn, admin: admin, teacher: teacher, student: student}
  end

  test "teacher edit modal shows teacher fields", %{conn: conn, teacher: teacher} do
    conn
    |> visit("/admin/users")
    |> click_button("#edit-user-#{teacher.id}", "编辑")
    |> assert_has("#edit-user-form")
    |> assert_has("label", "职称")
    |> assert_has("label", "所属院校")
  end

  test "student fields are editable and persisted", %{conn: conn, student: student} do
    conn
    |> visit("/admin/users")
    |> click_button("#edit-user-#{student.id}", "编辑")
    |> fill_in("学号", with: "2024001")
    |> fill_in("专业", with: "针灸推拿学")
    |> click_button("#edit-user-form button[type='submit']", "保存")
    |> assert_has("#flash-info")

    updated = Ash.get!(User, student.id, tenant: @tenant, authorize?: false)
    assert updated.student_no == "2024001"
    assert updated.major == "针灸推拿学"
  end

  test "uploads a student avatar image", %{conn: conn, student: student} do
    tmp_dir = Path.join(System.tmp_dir!(), "avatar-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    path = Path.join(tmp_dir, "avatar.png")
    File.write!(path, <<137, 80, 78, 71, 13, 10, 26, 10>>)

    conn
    |> visit("/admin/users")
    |> click_button("#edit-user-#{student.id}", "编辑")
    |> upload("选择图片", path, exact: false)
    |> click_button("#edit-user-form button[type='submit']", "保存")
    |> assert_has("#flash-info")

    loaded =
      User
      |> Ash.get!(student.id, tenant: @tenant, authorize?: false)
      |> Ash.load!(:avatar_url, tenant: @tenant, authorize?: false)

    assert loaded.avatar_url
  end

  test "assign student to a class and filter by class", %{conn: conn, student: student} do
    class_name = "临床 #{System.unique_integer([:positive])} 班"
    class_group = create_class(class_name)

    conn
    |> visit("/admin/users")
    |> click_button("#edit-user-#{student.id}", "编辑")
    |> select("班级", option: class_name)
    |> click_button("#edit-user-form button[type='submit']", "保存")
    |> assert_has("#flash-info")
    |> select("按班级筛选", option: class_name)
    |> assert_has("#user-#{student.id}")

    assert Ash.get!(User, student.id, tenant: @tenant, authorize?: false).class_group_id ==
             class_group.id
  end

  defp create_user(role, prefix) do
    User
    |> Ash.Changeset.for_create(
      :register_with_role,
      %{
        email: "#{prefix}-#{System.unique_integer([:positive])}@example.com",
        name: prefix,
        password: "password123",
        role: role
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
