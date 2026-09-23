defmodule TcmEduWeb.AdminUserImport do
  @moduledoc """
  xlsx template generation and import parsing for bulk-creating
  tenant users from the super admin / tenant admin user-management page.

  Template columns (`用户` sheet):

    | 邮箱 | 姓名 | 角色 | 初始密码 |

  * `邮箱`     — required, must look like an email address.
  * `姓名`     — optional.
  * `角色`     — required, dropdown (租户管理员 / 教师 / 学生).
  * `初始密码` — required, at least 6 characters.

  A second sheet (`填写说明`) documents the format.

  Mirrors the `TcmEduWeb.QuizImport` design (Elixlsx for the template,
  Xlsxir for the parser) so the admin side stays consistent with the
  existing teacher quiz-import flow.
  """

  alias Elixlsx.{Sheet, Workbook}

  @headers ["邮箱", "姓名", "角色", "初始密码"]
  @role_labels %{"租户管理员" => :tenant_admin, "教师" => :teacher, "学生" => :student}
  @role_order ["租户管理员", "教师", "学生"]
  @max_rows 200
  @email_regex ~r/^[^\s]+@[^\s]+\.[^\s]+$/

  @doc "Template file name for downloads."
  def template_filename, do: "user_import_template.xlsx"

  @doc "Expected header row of the import sheet."
  def headers, do: @headers

  @doc "Maximum number of data rows accepted per import."
  def max_rows, do: @max_rows

  @doc "Builds the import template workbook binary."
  def template_xlsx do
    users =
      %Sheet{name: "用户", rows: [@headers]}
      |> Sheet.add_data_validations("C2", "C201", @role_order)
      |> Sheet.set_pane_freeze(1, 0)
      |> Sheet.set_col_width("A", 32)
      |> Sheet.set_col_width("B", 20)
      |> Sheet.set_col_width("C", 14)
      |> Sheet.set_col_width("D", 20)

    guide = %Sheet{
      name: "填写说明",
      rows: [
        ["字段", "说明"],
        ["邮箱", "必填，必须是合法的邮箱格式；在租户内唯一"],
        ["姓名", "选填；留空则用邮箱前缀作为显示名"],
        ["角色", "必填，只能从下拉列表选择：租户管理员 / 教师 / 学生"],
        ["初始密码", "必填，至少 6 位；用户登录后可自行修改"],
        ["", ""],
        ["注意", "一次最多导入 #{@max_rows} 行；整行为空的行会被跳过；表头必须匹配模板"]
      ]
    }

    {:ok, {_name, binary}} =
      Elixlsx.write_to_memory(%Workbook{sheets: [users, guide]}, "template.xlsx")

    binary
  end

  @doc """
  Parses an xlsx file at `path` into user-create attributes.

  Returns `{:ok, rows, errors}` where:

    * `rows`   — list of `{excel_row_number, attrs}` for valid rows
    * `errors` — list of `{excel_row_number, message}` for invalid rows

  Returns `{:error, message}` when the file cannot be parsed or the
  header row doesn't match the template.
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
        {:error, "一次最多导入 #{@max_rows} 行，当前文件有 #{length(data)} 行"}
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

    [email_raw, name_raw, role_raw, password_raw] = cells

    with {:ok, email} <- parse_email(email_raw),
         {:ok, role} <- parse_role(role_raw),
         {:ok, password} <- parse_password(password_raw) do
      {:ok,
       %{
         email: String.downcase(email),
         name: empty_to_nil(name_raw),
         role: role,
         password: password
       }}
    end
  end

  defp pad_cells(cells, size) do
    cells ++ List.duplicate("", max(0, size - length(cells)))
  end

  defp parse_email(""), do: {:error, "邮箱不能为空"}

  defp parse_email(email) do
    email = String.trim(email)

    if Regex.match?(@email_regex, email) do
      {:ok, email}
    else
      {:error, "邮箱格式不正确"}
    end
  end

  defp parse_role(""), do: {:error, "角色不能为空"}

  defp parse_role(role) do
    case Map.fetch(@role_labels, String.trim(role)) do
      {:ok, atom} -> {:ok, atom}
      :error -> {:error, "角色必须是：#{Enum.join(@role_order, " / ")}"}
    end
  end

  defp parse_password(""), do: {:error, "初始密码不能为空"}

  defp parse_password(password) do
    if String.length(password) >= 6 do
      {:ok, password}
    else
      {:error, "初始密码至少 6 位"}
    end
  end

  defp cell_text(nil), do: ""
  defp cell_text(value) when is_binary(value), do: String.trim(value)
  defp cell_text(value) when is_number(value), do: to_string(value)
  defp cell_text(value), do: value |> to_string() |> String.trim()

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(value), do: String.trim(value)
end
