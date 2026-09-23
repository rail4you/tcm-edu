defmodule TcmEduWeb.AdminUserImportTest do
  @moduledoc """
  Covers the xlsx template + parser used by the admin user-management
  page for bulk-creating tenant users.
  """

  use ExUnit.Case, async: true

  alias Elixlsx.{Sheet, Workbook}
  alias TcmEduWeb.AdminUserImport

  defp write_xlsx(rows) do
    path =
      Path.join(
        System.tmp_dir!(),
        "admin-user-import-#{System.unique_integer([:positive])}.xlsx"
      )

    sheet = %Sheet{name: "用户", rows: rows}
    {:ok, {_name, binary}} = Elixlsx.write_to_memory(%Workbook{sheets: [sheet]}, "t.xlsx")
    File.write!(path, binary)
    on_exit(fn -> File.rm(path) end)
    path
  end

  test "template has dropdown validation on the role column" do
    assert byte_size(AdminUserImport.template_xlsx()) > 0

    {:ok, files} = :zip.unzip(AdminUserImport.template_xlsx(), [:memory])

    sheet_xml =
      Enum.find_value(files, fn {name, content} ->
        if name == ~c"xl/worksheets/sheet1.xml", do: content
      end)

    assert sheet_xml =~ "dataValidation"
    assert sheet_xml =~ "租户管理员"
    assert sheet_xml =~ "教师"
    assert sheet_xml =~ "学生"
  end

  test "parses valid rows and reports row errors" do
    path =
      write_xlsx([
        AdminUserImport.headers(),
        ["alice@example.com", "Alice", "教师", "password123"],
        ["bob@example.com", "", "学生", "secret123"],
        ["carol@example.com", "Carol", "租户管理员", "carol123"],
        ["bad-email", "", "教师", "password123"],
        ["dave@example.com", "", "旁观者", "password123"],
        ["eve@example.com", "", "教师", "123"],
        ["frank@example.com", "", "教师", ""]
      ])

    assert {:ok, rows, errors} = AdminUserImport.import_file(path)

    assert {2, %{email: "alice@example.com", role: :teacher, name: "Alice"}} =
             Enum.find(rows, fn {n, _} -> n == 2 end)

    assert {3, %{email: "bob@example.com", role: :student, name: nil}} =
             Enum.find(rows, fn {n, _} -> n == 3 end)

    assert {4, %{role: :tenant_admin}} = Enum.find(rows, fn {n, _} -> n == 4 end)

    assert length(rows) == 3

    assert {5, "邮箱格式不正确"} in errors
    assert {6, "角色必须是：租户管理员 / 教师 / 学生"} in errors
    assert {7, "初始密码至少 6 位"} in errors
    assert {8, "初始密码不能为空"} in errors
  end

  test "lower-cases email but preserves other fields" do
    path =
      write_xlsx([
        AdminUserImport.headers(),
        ["MIXED@Example.COM", "Mixed Case", "学生", "password123"]
      ])

    assert {:ok, [{2, attrs}], []} = AdminUserImport.import_file(path)
    assert attrs.email == "mixed@example.com"
    assert attrs.name == "Mixed Case"
  end

  test "rejects files with mismatched headers" do
    path = write_xlsx([["a", "b"], ["foo", "bar"]])
    assert {:error, message} = AdminUserImport.import_file(path)
    assert message =~ "表头不匹配"
  end

  test "rejects too many rows" do
    too_many =
      [AdminUserImport.headers()] ++
        Enum.map(1..(AdminUserImport.max_rows() + 1), fn i ->
          ["user-#{i}@example.com", "u#{i}", "学生", "password123"]
        end)

    path = write_xlsx(too_many)
    assert {:error, message} = AdminUserImport.import_file(path)
    assert message =~ "一次最多导入"
  end

  test "skips fully blank rows" do
    path =
      write_xlsx([
        AdminUserImport.headers(),
        ["", "", "", ""],
        ["valid@example.com", "Valid", "教师", "password123"],
        ["", "", "", ""]
      ])

    # Row numbers renumber after blank rows are filtered out (same convention
    # as TcmEduWeb.QuizImport).
    assert {:ok, [{2, %{email: "valid@example.com"}}], []} = AdminUserImport.import_file(path)
  end
end
