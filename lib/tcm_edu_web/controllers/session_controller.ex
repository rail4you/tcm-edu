defmodule TcmEduWeb.SessionController do
  @moduledoc """
  The single session entrance for the unified login page (`/login`).

  The trigger-action form posts `login[tab]` (`student` | `teacher` |
  `admin`) plus `login[sub]` (`super` | `tenant` for the admin tab) and
  `login[tenant]` (schema name, required for tenant users in the UI).
  Each branch verifies credentials through the portal's auth module,
  writes that portal's session and redirects to its home.

  Legacy per-portal login URLs redirect here via `legacy_login/2`.
  """

  use TcmEduWeb, :controller

  alias TcmEduWeb.AdminAuth
  alias TcmEduWeb.StudentAuth
  alias TcmEduWeb.TeacherAuth

  def create(conn, %{"login" => %{"tab" => "teacher"} = params}) do
    tenant = tenant_param(params)

    case TeacherAuth.authenticate(params["email"] || "", params["password"] || "", tenant) do
      {:ok, teacher} ->
        conn
        |> put_session_values(TeacherAuth.build_session(teacher))
        |> configure_session(renew: true)
        |> put_flash(:info, "欢迎回来，#{teacher.name}")
        |> redirect(to: "/teacher")

      {:error, :invalid_credentials} ->
        deny(conn, "账号或密码错误", "teacher")
    end
  end

  def create(conn, %{"login" => %{"tab" => "admin"} = params}) do
    sub = if params["sub"] == "tenant", do: "tenant", else: "super"
    tenant = tenant_param(params)

    case AdminAuth.authenticate(params["email"] || "", params["password"] || "", sub, tenant) do
      {:ok, admin} ->
        conn
        |> put_session_values(AdminAuth.build_session(admin))
        |> configure_session(renew: true)
        |> put_flash(:info, "欢迎回来，#{admin.name}")
        |> redirect(to: "/admin")

      {:error, :invalid_credentials} ->
        deny(conn, "账号或密码错误", "admin", sub)
    end
  end

  def create(conn, %{"login" => %{"tab" => _} = params}) do
    # Default tab: student.
    tenant = tenant_param(params)

    case StudentAuth.authenticate(params["email"] || "", params["password"] || "", tenant) do
      {:ok, student} ->
        conn
        |> put_session_values(StudentAuth.build_session(student))
        |> configure_session(renew: true)
        |> put_flash(:info, "欢迎回来，#{student.name}")
        |> redirect(to: "/my-learning")

      {:error, :invalid_credentials} ->
        deny(conn, "账号或密码错误", "student")
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

  defp tenant_param(%{"tenant" => tenant}) when is_binary(tenant) do
    tenant = String.trim(tenant)
    if tenant == "", do: nil, else: tenant
  end

  defp tenant_param(_), do: nil

  # 失败回跳保留 tab/sub（mount 会据此恢复选项卡），避免“输错一次就重置角色”。
  defp deny(conn, message, tab \\ "student", sub \\ "super") do
    target =
      if tab == "admin",
        do: "/login?tab=admin&admin=#{sub}",
        else: "/login?tab=#{tab}"

    conn
    |> put_flash(:error, message)
    |> redirect(to: target)
  end

  defp put_session_values(conn, values) when is_map(values) do
    Enum.reduce(values, conn, fn {key, value}, conn ->
      put_session(conn, key, value)
    end)
  end
end
