defmodule TcmEduWeb.TeacherQuizImportTest do
  @moduledoc """
  End-to-end coverage for the quiz import flow (`/teacher/quiz`) using
  PhoenixTest instead of a real browser:

    * downloading the xlsx template,
    * importing a filled-in file (2 valid rows + 1 invalid row),
    * seeing per-row errors and the created questions.
  """

  use TcmEduWeb.LiveViewCase

  import PhoenixTest

  alias TcmEdu.Accounts.User
  alias TcmEdu.Quiz.QuestionBank
  alias TcmEduWeb.QuizImport

  @tenant "tenant_default"

  setup %{conn: conn} do
    teacher =
      User
      |> Ash.Changeset.for_create(
        :register_with_role,
        %{
          email: "quiz-import-#{System.unique_integer([:positive])}@example.com",
          name: "Import Teacher",
          password: "password123",
          role: :teacher
        },
        tenant: @tenant,
        authorize?: false
      )
      |> Ash.create!()

    bank =
      QuestionBank
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "导入验证库 #{System.unique_integer([:positive])}",
          subject: :traditional_chinese_medicine
        },
        actor: teacher,
        tenant: @tenant
      )
      |> Ash.create!()

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "teacher_id" => teacher.id,
        "teacher_role" => "teacher",
        "teacher_tenant" => @tenant,
        "teacher_email" => to_string(teacher.email),
        "teacher_name" => "Import Teacher"
      })
      |> PhoenixTest.put_endpoint(TcmEduWeb.Endpoint)

    {:ok, conn: conn, teacher: teacher, bank: bank}
  end

  test "teacher downloads the import template", %{conn: conn, bank: bank} do
    conn
    |> visit("/teacher/quiz")
    |> click_button(bank.name)
    |> click_link("下载模板")
    |> assert_download("quiz_import_template.xlsx")
  end

  test "teacher imports questions from xlsx", %{conn: conn, bank: bank} do
    tmp_dir = Path.join(System.tmp_dir!(), "quiz-import-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    path = Path.join(tmp_dir, "import.xlsx")
    File.write!(path, fixture_xlsx())

    conn
    |> visit("/teacher/quiz")
    |> click_button(bank.name)
    |> click_button("导入习题")
    |> upload("导入文件", path, exact: false)
    |> click_button("开始导入")
    |> assert_has("p", "成功导入 2 题")
    |> assert_has("#import-error-4", "题型必须是")
    |> click_button("完成")
    |> assert_has("td", "E2E题干一")
    |> assert_has("td", "E2E题干二")
  end

  defp fixture_xlsx do
    alias Elixlsx.{Sheet, Workbook}

    rows = [
      QuizImport.headers(),
      ["单选", 3, "E2E题干一", "甲", "乙", "丙", "", "", "", "B", "解析一"],
      ["判断", "", "E2E题干二", "", "", "", "", "", "", "对", ""],
      ["问答", 3, "E2E题干三", "", "", "", "", "", "", "", ""]
    ]

    sheet = %Sheet{name: "题目", rows: rows}
    {:ok, {_name, binary}} = Elixlsx.write_to_memory(%Workbook{sheets: [sheet]}, "import.xlsx")
    binary
  end
end
