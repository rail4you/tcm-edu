defmodule TcmEduWeb.SessionController do
  @moduledoc """
  The single session entrance for the unified login page (`/login`).

  The trigger-action form posts `login[mode]` (`tenant` | `super`) plus
  `login[role]` (`student` | `teacher` | `tenant_admin`) and
  `login[tenant]` (schema name, required for tenant users in the UI).
  Legacy `login[tab]` (`student` | `teacher` | `admin`) + `login[sub]`
  params are still honored. Each branch verifies credentials through
  the portal's auth module, writes that portal's session and redirects
  to its home.

  Legacy per-portal login URLs redirect here via `legacy_login/2`.
  """

  use TcmEduWeb, :controller

  alias TcmEduWeb.AdminAuth
  alias TcmEduWeb.StudentAuth
  alias TcmEduWeb.TeacherAuth

  def create(conn, %{"login" => params}) do
    tenant = tenant_param(params)
    identity = params["email"] || ""
    password = params["password"] || ""

    case login_kind(params) do
      :super ->
        case AdminAuth.authenticate(identity, password, "super") do
          {:ok, admin} ->
            conn
            |> put_session_values(AdminAuth.build_session(admin))
            |> configure_session(renew: true)
            |> put_flash(:info, "欢迎回来，#{admin.name}")
            |> redirect(to: "/admin")

          {:error, :invalid_credentials} ->
            deny(conn, "账号或密码错误", :super)
        end

      :tenant_admin ->
        case AdminAuth.authenticate(identity, password, "tenant", tenant) do
          {:ok, admin} ->
            conn
            |> put_session_values(AdminAuth.build_session(admin))
            |> configure_session(renew: true)
            |> put_flash(:info, "欢迎回来，#{admin.name}")
            |> redirect(to: "/admin")

          {:error, :invalid_credentials} ->
            deny(conn, "账号或密码错误", :tenant_admin)
        end

      :teacher ->
        case TeacherAuth.authenticate(identity, password, tenant) do
          {:ok, teacher} ->
            conn
            |> put_session_values(TeacherAuth.build_session(teacher))
            |> configure_session(renew: true)
            |> put_flash(:info, "欢迎回来，#{teacher.name}")
            |> redirect(to: "/teacher")

          {:error, :invalid_credentials} ->
            deny(conn, "账号或密码错误", :teacher)
        end

      :student ->
        case StudentAuth.authenticate(identity, password, tenant) do
          {:ok, student} ->
            conn
            |> put_session_values(StudentAuth.build_session(student))
            |> configure_session(renew: true)
            |> put_flash(:info, "欢迎回来，#{student.name}")
            |> redirect(to: "/my-learning")

          {:error, :invalid_credentials} ->
            deny(conn, "账号或密码错误", :student)
        end
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

  # 新参数优先，旧 tab/sub 兼容。
  defp login_kind(%{"mode" => "super"}), do: :super
  defp login_kind(%{"role" => "tenant_admin"}), do: :tenant_admin
  defp login_kind(%{"role" => "teacher"}), do: :teacher
  defp login_kind(%{"role" => "student"}), do: :student
  defp login_kind(%{"tab" => "teacher"}), do: :teacher
  defp login_kind(%{"tab" => "admin", "sub" => "tenant"}), do: :tenant_admin
  defp login_kind(%{"tab" => "admin"}), do: :super
  defp login_kind(_), do: :student

  # 失败回跳保留 mode/role，避免“输错一次就重置选项”。
  defp deny(conn, message, kind \\ :student) do
    target =
      case kind do
        :super -> "/login?mode=super"
        :tenant_admin -> "/login?role=tenant_admin"
        :teacher -> "/login?role=teacher"
        _ -> "/login"
      end

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
