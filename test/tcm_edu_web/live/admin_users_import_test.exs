defmodule TcmEduWeb.AdminUsersImportTest do
  @moduledoc """
  End-to-end coverage for the admin user-import flow at `/admin/users`:

    * downloading the xlsx template,
    * importing a filled-in file (2 valid rows + 1 invalid row),
    * seeing per-row errors and the created users.
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  require Ash.Query

  alias TcmEdu.Accounts.User
  alias TcmEdu.Classes.ClassGroup
  alias TcmEdu.System.SuperAdmin
  alias TcmEduWeb.AdminUserImport

  @super_email "admin-user-import-#{System.unique_integer([:positive])}@example.com"
  @super_password "password123"
  @tenant "tenant_default"

  setup %{conn: conn} do
    admin =
      SuperAdmin
      |> Ash.Changeset.for_create(
        :register,
        %{email: @super_email, name: "Import Admin", password: @super_password},
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
        "admin_name" => "Import Admin"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, admin: admin}
  end

  test "admin downloads the user-import template", %{conn: conn} do
    conn
    |> visit("/admin/users")
    |> click_link("下载导入模板")
    |> assert_download("user_import_template.xlsx")
  end

  test "admin imports users from xlsx and sees per-row errors", %{conn: conn} do
    tmp_dir =
      Path.join(System.tmp_dir!(), "admin-user-import-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    path = Path.join(tmp_dir, "users.xlsx")
    File.write!(path, fixture_xlsx())

    conn
    |> visit("/admin/users")
    |> click_button("批量导入")
    |> upload("导入文件", path, exact: false)
    |> click_button("开始导入")
    |> assert_has("p", "成功导入 2 个用户")
    |> assert_has("#user-import-error-3", "邮箱格式不正确")
    |> click_button("完成")
    |> assert_has("td", "alice@example.com")
    |> assert_has("td", "bob@example.com")
    |> refute_has("td", "bad-email")

    # Side-effect: users are persisted in the tenant_default schema.
    emails =
      User
      |> Ash.Query.filter(email in ["alice@example.com", "bob@example.com"])
      |> Ash.read!(authorize?: false, tenant: @tenant)
      |> Enum.map(fn user -> to_string(user.email) end)
      |> Enum.sort()

    assert emails == ["alice@example.com", "bob@example.com"]

    # 班级列填了名称 → 自动创建班级并关联学生。
    assert [%ClassGroup{id: class_id, name: "2024 级临床 1 班"}] =
             Ash.read!(ClassGroup, tenant: @tenant, authorize?: false)

    bob =
      User
      |> Ash.Query.filter(email == "bob@example.com")
      |> Ash.read_one!(authorize?: false, tenant: @tenant)

    assert bob.class_group_id == class_id
  end

  defp fixture_xlsx do
    alias Elixlsx.{Sheet, Workbook}

    rows = [
      AdminUserImport.headers(),
      ["alice@example.com", "Alice 教师", "教师", "", "password123"],
      ["bad-email", "", "学生", "", "password123"],
      ["bob@example.com", "Bob 学生", "学生", "2024 级临床 1 班", "password123"]
    ]

    sheet = %Sheet{name: "用户", rows: rows}
    {:ok, {_name, binary}} = Elixlsx.write_to_memory(%Workbook{sheets: [sheet]}, "users.xlsx")
    binary
  end
end
