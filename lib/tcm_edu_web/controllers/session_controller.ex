defmodule TcmEduWeb.SessionController do
  @moduledoc """
  The single session entrance for the unified login page (`/login`).

  The trigger-action form posts `login[tab]` (`student` | `teacher` |
  `admin`) plus `login[sub]` (`super` | `tenant` for the admin tab).
  Each branch verifies credentials through the portal's auth module,
  writes that portal's session and redirects to its home.

  Legacy per-portal login URLs redirect here via `legacy_login/2`.
  """

  use TcmEduWeb, :controller

  alias TcmEduWeb.AdminAuth
  alias TcmEduWeb.StudentAuth
  alias TcmEduWeb.TeacherAuth

  def create(conn, %{"login" => %{"tab" => "teacher"} = params}) do
    case TeacherAuth.authenticate(params["email"] || "", params["password"] || "") do
      {:ok, teacher} ->
        conn
        |> put_session_values(TeacherAuth.build_session(teacher))
        |> configure_session(renew: true)
        |> put_flash(:info, "欢迎回来，#{teacher.name}")
        |> redirect(to: "/teacher")

      {:error, :invalid_credentials} ->
        deny(conn, "邮箱或密码错误")
    end
  end

  def create(conn, %{"login" => %{"tab" => "admin"} = params}) do
    sub = if params["sub"] == "tenant", do: "tenant", else: "super"

    case AdminAuth.authenticate(params["email"] || "", params["password"] || "", sub) do
      {:ok, admin} ->
        conn
        |> put_session_values(AdminAuth.build_session(admin))
        |> configure_session(renew: true)
        |> put_flash(:info, "欢迎回来，#{admin.name}")
        |> redirect(to: "/admin")

      {:error, :invalid_credentials} ->
        deny(conn, "邮箱或密码错误")
    end
  end

  def create(conn, %{"login" => %{"tab" => _} = params}) do
    # Default tab: student.
    case StudentAuth.authenticate(params["email"] || "", params["password"] || "") do
      {:ok, student} ->
        conn
        |> put_session_values(StudentAuth.build_session(student))
        |> configure_session(renew: true)
        |> put_flash(:info, "欢迎回来，#{student.name}")
        |> redirect(to: "/my-learning")

      {:error, :invalid_credentials} ->
        deny(conn, "邮箱或密码错误")
    end
  end

  def create(conn, _params) do
    deny(conn, "请填写完整的登录信息")
  end

  @doc "Legacy per-portal login URLs (`/admin/login`, `/teacher/login`)."
  def legacy_login(conn, _params) do
    conn
    |> put_flash(:info, "登录已统一，请在这里选择身份")
    |> redirect(to: "/login")
  end

  @doc "Single logout: drops the whole session and returns to login."
  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/login")
  end

  defp deny(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: "/login")
  end

  defp put_session_values(conn, values) when is_map(values) do
    Enum.reduce(values, conn, fn {key, value}, conn ->
      put_session(conn, key, value)
    end)
  end
end
