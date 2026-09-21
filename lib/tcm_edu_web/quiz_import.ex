defmodule TcmEduWeb.QuizImport do
  @moduledoc """
  xlsx template generation and import parsing for teacher question banks.

  Template columns (`题目` sheet):

    | 题型 | 难度 | 题干 | 选项A | … | 选项F | 正确答案 | 解析 |

  * `题型` — restricted to a dropdown list (`单选/多选/判断/简答`),
    required.
  * `难度` — 1-5, blank means 3.
  * `题干` — required.
  * `选项A`–`选项F` — option text; blank means "no such option".
    Only used by single/multi choice.
  * `正确答案` — single: one letter (`B`); multi: comma-separated
    letters (`A,C`); judge: `对`/`错`; essay: reference answer text.
  * `解析` — optional explanation shown to students.

  A second sheet (`填写说明`) documents the format for teachers.
  """

  alias Elixlsx.{Sheet, Workbook}

  @headers ["题型", "难度", "题干", "选项A", "选项B", "选项C", "选项D", "选项E", "选项F", "正确答案", "解析"]
  @option_letters ~w(A B C D E F)

  @type_order ["单选", "多选", "判断", "简答"]

  @type_labels %{
    "单选" => :single,
    "多选" => :multi,
    "判断" => :judge,
    "简答" => :essay
  }

  @max_rows 200

  @doc "Template file name for downloads."
  def template_filename, do: "quiz_import_template.xlsx"

  @doc "Expected header row of the import sheet."
  def headers, do: @headers

  @doc "Maximum number of data rows accepted per import."
  def max_rows, do: @max_rows

  @doc "Builds the import template workbook binary."
  def template_xlsx do
    questions =
      %Sheet{name: "题目", rows: [@headers]}
      |> Sheet.add_data_validations("A2", "A201", @type_order)
      |> Sheet.set_pane_freeze(1, 0)
      |> Sheet.set_col_width("A", 10)
      |> Sheet.set_col_width("B", 8)
      |> Sheet.set_col_width("C", 50)
      |> Sheet.set_col_width("D", 24)
      |> Sheet.set_col_width("E", 24)
      |> Sheet.set_col_width("F", 24)
      |> Sheet.set_col_width("G", 24)
      |> Sheet.set_col_width("H", 24)
      |> Sheet.set_col_width("I", 24)
      |> Sheet.set_col_width("J", 16)
      |> Sheet.set_col_width("K", 40)

    guide = %Sheet{
      name: "填写说明",
      rows: [
        ["字段", "说明"],
        ["题型", "必填，只能从下拉列表选择：单选 / 多选 / 判断 / 简答"],
        ["难度", "1-5 的整数，留空默认为 3"],
        ["题干", "必填，支持 markdown，最长 2000 字"],
        ["选项A-选项F", "选择题填写，留空表示没有该选项；判断/简答题忽略"],
        ["正确答案", "单选填一个字母（如 B）；多选填多个字母逗号分隔（如 A,C）；判断填 对 或 错；简答填参考答案"],
        ["解析", "选填，学生答题后可见"],
        ["", ""],
        ["注意", "一次最多导入 #{@max_rows} 题；题干为空的行会被跳过"]
      ]
    }

    {:ok, {_name, binary}} =
      Elixlsx.write_to_memory(%Workbook{sheets: [questions, guide]}, "template.xlsx")

    binary
  end

  @doc """
  Parses an xlsx file at `path` into question attributes.

  Returns `{:ok, rows, errors}` where `rows` is a list of
  `{excel_row_number, attrs}` tuples and `errors` is a list of
  `{excel_row_number, message}` tuples. Returns `{:error, message}` when
  the file itself cannot be read or the header row does not match.
  """
  def import_file(path) when is_binary(path) do
    rows =
      try do
        case Xlsxir.extract(path, 0) do
          {:ok, pid} ->
            try do
              Xlsxir.get_list(pid)
            after
              Xlsxir.close(pid)
            end

          {:error, _} ->
            :unreadable
        end
      rescue
        _ -> :unreadable
      catch
        _, _ -> :unreadable
      end

    case rows do
      :unreadable -> {:error, "文件解析失败，请确认是有效的 xlsx 文件"}
      [] -> {:error, "文件中没有内容，请使用下载的模板填写"}
      [header | data] -> parse_rows(header, data)
    end
  end

  defp parse_rows(header, data) do
    if Enum.map(header, &cell_text/1) != @headers do
      {:error, "表头不匹配，请使用页面下载的模板填写后再导入"}
    else
      data = Enum.reject(data, &blank_row?/1)

      if length(data) > @max_rows do
        {:error, "一次最多导入 #{@max_rows} 题，当前文件有 #{length(data)} 题"}
      else
        {ok, errors} =
          data
          |> Enum.with_index(2)
          |> Enum.reduce({[], []}, fn {row, row_number}, {ok_acc, err_acc} ->
            case parse_row(row) do
              {:ok, attrs} -> {[{row_number, attrs} | ok_acc], err_acc}
              {:error, message} -> {ok_acc, [{row_number, message} | err_acc]}
            end
          end)

        {:ok, Enum.reverse(ok), Enum.reverse(errors)}
      end
    end
  end

  defp blank_row?(row) do
    row |> Enum.take(length(@headers)) |> Enum.all?(&(&1 |> cell_text() |> Kernel.==("")))
  end

  defp parse_row(row) do
    cells =
      row
      |> Enum.take(length(@headers))
      |> Enum.map(&cell_text/1)
      |> pad_cells(length(@headers))

    [
      type_label,
      difficulty_raw,
      stem,
      opt_a,
      opt_b,
      opt_c,
      opt_d,
      opt_e,
      opt_f,
      answer_raw,
      explanation
    ] =
      cells

    with {:ok, type} <- parse_type(type_label),
         {:ok, difficulty} <- parse_difficulty(difficulty_raw),
         {:ok, stem} <- parse_stem(stem),
         {:ok, options, answer} <-
           parse_body(type, [opt_a, opt_b, opt_c, opt_d, opt_e, opt_f], answer_raw) do
      {:ok,
       %{
         type: type,
         difficulty: difficulty,
         stem: stem,
         options: options,
         answer: empty_to_nil(answer),
         explanation: empty_to_nil(explanation)
       }}
    end
  end

  defp pad_cells(cells, size) do
    cells ++ List.duplicate("", max(0, size - length(cells)))
  end

  defp parse_type(label) do
    case Map.fetch(@type_labels, label) do
      {:ok, type} -> {:ok, type}
      :error -> {:error, "题型必须是：#{Enum.join(@type_order, " / ")}"}
    end
  end

  defp parse_difficulty(""), do: {:ok, 3}

  defp parse_difficulty(raw) do
    case Integer.parse(raw) do
      {n, ""} when n in 1..5 ->
        {:ok, n}

      _ ->
        case Float.parse(raw) do
          {f, ""} when f >= 1 and f <= 5 and round(f) == f -> {:ok, round(f)}
          _ -> {:error, "难度必须是 1-5 的整数"}
        end
    end
  end

  defp parse_stem(""), do: {:error, "题干不能为空"}

  defp parse_stem(stem) do
    if String.length(stem) > 2000 do
      {:error, "题干不能超过 2000 字"}
    else
      {:ok, stem}
    end
  end

  defp parse_body(:essay, _option_cells, answer), do: {:ok, [], answer}
  defp parse_body(:judge, _option_cells, answer), do: parse_judge_answer(answer)

  defp parse_body(type, option_cells, answer) when type in [:single, :multi] do
    options =
      @option_letters
      |> Enum.zip(option_cells)
      |> Enum.reject(fn {_letter, text} -> text == "" end)
      |> Enum.map(fn {letter, text} -> %{label: letter, text: text} end)

    with :ok <- require_option_count(options),
         {:ok, correct} <- parse_letters(answer, options),
         :ok <- require_correct_count(type, correct) do
      options =
        Enum.map(options, fn opt -> Map.put(opt, :correct, opt.label in correct) end)

      {:ok, options, nil}
    end
  end

  defp parse_judge_answer(answer) when answer in ["对", "错"], do: {:ok, [], answer}
  defp parse_judge_answer(_), do: {:error, "判断题的正确答案只能填 对 或 错"}

  defp require_option_count(options) when length(options) >= 2, do: :ok
  defp require_option_count(_), do: {:error, "选择题至少需要 2 个有效选项"}

  defp parse_letters("", _options), do: {:error, "请填写正确答案"}

  defp parse_letters(raw, options) do
    valid = MapSet.new(options, & &1.label)

    letters =
      raw
      |> String.upcase()
      |> String.split([",", "，", "、", " ", ";", "；"], trim: true)
      |> Enum.uniq()

    invalid = Enum.reject(letters, &MapSet.member?(valid, &1))

    cond do
      letters == [] -> {:error, "请填写正确答案"}
      invalid != [] -> {:error, "正确答案 #{Enum.join(invalid, "、")} 没有对应的非空选项"}
      true -> {:ok, letters}
    end
  end

  defp require_correct_count(:single, [_]), do: :ok
  defp require_correct_count(:single, _), do: {:error, "单选题请只填写一个正确答案"}
  defp require_correct_count(:multi, [_ | _]), do: :ok
  defp require_correct_count(:multi, _), do: {:error, "多选题请至少填写一个正确答案"}

  defp cell_text(nil), do: ""
  defp cell_text(value) when is_binary(value), do: String.trim(value)
  defp cell_text(value) when is_number(value), do: to_string(value)
  defp cell_text(value), do: value |> to_string() |> String.trim()

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
