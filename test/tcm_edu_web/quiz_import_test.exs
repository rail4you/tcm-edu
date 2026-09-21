defmodule TcmEduWeb.QuizImportTest do
  use ExUnit.Case, async: true

  alias TcmEduWeb.QuizImport

  defp write_xlsx(rows) do
    alias Elixlsx.{Sheet, Workbook}

    path =
      Path.join(
        System.tmp_dir!(),
        "quiz-import-#{System.unique_integer([:positive])}.xlsx"
      )

    sheet = %Sheet{name: "题目", rows: rows}
    {:ok, {_name, binary}} = Elixlsx.write_to_memory(%Workbook{sheets: [sheet]}, "t.xlsx")
    File.write!(path, binary)
    on_exit(fn -> File.rm(path) end)
    path
  end

  test "template has dropdown validation on the type column" do
    {:ok, {_name, binary}} =
      Elixlsx.write_to_memory(
        %Elixlsx.Workbook{sheets: [%Elixlsx.Sheet{name: "s", rows: [["a"]]}]},
        "t.xlsx"
      )

    assert is_binary(binary)
    assert byte_size(QuizImport.template_xlsx()) > 0

    # The generated template must carry an xlsx list validation so the
    # type column is restricted to a dropdown in Excel/WPS.
    {:ok, files} = :zip.unzip(QuizImport.template_xlsx(), [:memory])

    sheet_xml =
      Enum.find_value(files, fn {name, content} ->
        if name == ~c"xl/worksheets/sheet1.xml", do: content
      end)

    assert sheet_xml =~ "dataValidation"
    assert sheet_xml =~ "单选"
  end

  test "parses valid rows and reports row errors" do
    path =
      write_xlsx([
        QuizImport.headers(),
        ["单选", 3, "题干一", "甲", "乙", "", "", "", "", "A", "解析"],
        ["多选", "", "题干二", "甲", "乙", "丙", "", "", "", "A,C", ""],
        ["判断", 2, "题干三", "", "", "", "", "", "", "错", ""],
        ["简答", 5, "题干四", "", "", "", "", "", "", "参考答案", ""],
        ["问答", 3, "题干五", "", "", "", "", "", "", "", ""]
      ])

    assert {:ok, rows, errors} = QuizImport.import_file(path)
    assert length(rows) == 4
    assert errors == [{6, "题型必须是：单选 / 多选 / 判断 / 简答"}]

    assert {2, %{type: :single, difficulty: 3, stem: "题干一"}} =
             Enum.find(rows, fn {n, _} -> n == 2 end)

    assert {3, %{type: :multi, difficulty: 3}} = Enum.find(rows, fn {n, _} -> n == 3 end)

    assert {5, %{type: :essay, difficulty: 5, answer: "参考答案"}} =
             Enum.find(rows, fn {n, _} -> n == 5 end)
  end

  test "rejects files with mismatched headers" do
    path = write_xlsx([["a", "b"], ["单选", "题干"]])
    assert {:error, message} = QuizImport.import_file(path)
    assert message =~ "表头不匹配"
  end

  test "rejects single choice with wrong correct count" do
    path =
      write_xlsx([
        QuizImport.headers(),
        ["单选", 3, "题干", "甲", "乙", "", "", "", "", "A,B", ""]
      ])

    assert {:ok, [], [{2, "单选题请只填写一个正确答案"}]} = QuizImport.import_file(path)
  end
end
