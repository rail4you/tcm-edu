defmodule TcmEduWeb.AdminSessionController do
  @moduledoc """
  Creates/destroys the admin session cookie for the LiveView admin panel.

  The login LiveView (`AdminLoginLive`) validates the form client-side and
  then natively POSTs here via `phx-trigger-action`; this controller
  re-verifies the credentials, writes the session and redirects.
  """

  use TcmEduWeb, :controller

  alias TcmEduWeb.AdminAuth

  def create(conn, %{"admin" => %{"email" => email, "password" => password} = params}) do
    mode = Map.get(params, "mode", "super")

    case AdminAuth.authenticate(email, password, mode) do
      {:ok, admin} ->
        conn
        |> put_session_values(AdminAuth.build_session(admin))
        |> configure_session(renew: true)
        |> put_flash(:info, "欢迎回来，#{admin.name}")
        |> redirect(to: "/admin")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "邮箱或密码错误")
        |> redirect(to: "/admin/login")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "请填写完整的登录信息")
    |> redirect(to: "/admin/login")
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/admin/login")
  end

  defp put_session_values(conn, values) when is_map(values) do
    Enum.reduce(values, conn, fn {key, value}, conn ->
      put_session(conn, key, value)
    end)
  end
end
