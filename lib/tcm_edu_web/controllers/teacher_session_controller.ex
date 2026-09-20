defmodule TcmEduWeb.TeacherSessionController do
  @moduledoc """
  Creates/destroys the teacher session cookie for the LiveView teacher
  portal. The login LiveView natively POSTs here via `phx-trigger-action`.
  """

  use TcmEduWeb, :controller

  alias TcmEduWeb.TeacherAuth

  def create(conn, %{"teacher" => %{"email" => email, "password" => password}}) do
    case TeacherAuth.authenticate(email, password) do
      {:ok, teacher} ->
        conn
        |> put_session_values(TeacherAuth.build_session(teacher))
        |> configure_session(renew: true)
        |> put_flash(:info, "欢迎回来，#{teacher.name}")
        |> redirect(to: "/teacher")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "邮箱或密码错误")
        |> redirect(to: "/teacher/login")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "请填写完整的登录信息")
    |> redirect(to: "/teacher/login")
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/teacher/login")
  end

  defp put_session_values(conn, values) when is_map(values) do
    Enum.reduce(values, conn, fn {key, value}, conn ->
      put_session(conn, key, value)
    end)
  end
end
