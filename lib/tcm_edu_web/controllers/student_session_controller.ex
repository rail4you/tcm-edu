defmodule TcmEduWeb.StudentSessionController do
  @moduledoc """
  Creates/destroys the student session cookie. The login LiveView natively
  POSTs here via `phx-trigger-action` with `student[mode]` of `"login"` or
  `"register"`.
  """

  use TcmEduWeb, :controller

  alias TcmEduWeb.StudentAuth

  def create(conn, %{"student" => %{"mode" => "register"} = params}) do
    email = Map.get(params, "email", "")
    name = Map.get(params, "name", "")
    password = Map.get(params, "password", "")

    case StudentAuth.register(email, name, password) do
      {:ok, student} ->
        conn
        |> put_session_values(StudentAuth.build_session(student))
        |> configure_session(renew: true)
        |> put_flash(:info, "注册成功，欢迎加入中医学习之旅")
        |> redirect(to: "/my-learning")

      {:error, message} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: "/login")
    end
  end

  def create(conn, %{"student" => %{"email" => email, "password" => password}}) do
    case StudentAuth.authenticate(email, password) do
      {:ok, student} ->
        conn
        |> put_session_values(StudentAuth.build_session(student))
        |> configure_session(renew: true)
        |> put_flash(:info, "欢迎回来，#{student.name}")
        |> redirect(to: "/my-learning")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "邮箱或密码错误")
        |> redirect(to: "/login")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "请填写完整的登录信息")
    |> redirect(to: "/login")
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end

  defp put_session_values(conn, values) when is_map(values) do
    Enum.reduce(values, conn, fn {key, value}, conn ->
      put_session(conn, key, value)
    end)
  end
end
