defmodule TcmEduWeb.QuizTemplateController do
  @moduledoc """
  Serves the question import template (`/teacher/quiz/template.xlsx`).

  Teachers (and tenant admins who teach) download the template, fill in
  questions following the `填写说明` sheet, and upload the result through
  the import dialog on the quiz page.
  """

  use TcmEduWeb, :controller

  alias TcmEduWeb.QuizImport
  alias TcmEduWeb.TeacherAuth

  plug :require_teacher when action in [:template]

  def template(conn, _params) do
    send_download(conn, {:binary, QuizImport.template_xlsx()},
      filename: QuizImport.template_filename()
    )
  end

  defp require_teacher(conn, _opts) do
    case TeacherAuth.current_teacher(get_session(conn)) do
      {:ok, _teacher} ->
        conn

      :error ->
        conn
        |> put_flash(:error, "请先登录教师端")
        |> redirect(to: "/login")
        |> halt()
    end
  end
end
