defmodule TcmEduWeb.AuthController do
  @moduledoc """
  Authentication controller that handles password-based sign-in/sign-up
  and returns JSON responses with bearer tokens for the SPA client.

  Three login flows:

    1. `POST /api/auth/sign_in`         — 租户用户（AshAuthentication 标准流程）
    2. `POST /api/auth/super_admin_sign_in` — 超管（自定义 action）
    3. `GET  /api/auth/me`              — 当前用户信息
  """

  use TcmEduWeb, :controller
  use AshAuthentication.Phoenix.Controller

  require Logger

  alias TcmEduWeb.AuthToken
  alias TcmEdu.System.SuperAdmin

  @doc """
  Called on successful authentication (sign-in or registration).

  在标准 AshAuthentication token 基础上重新签名，补上 `tenant` / `role` claims，
  以便 `SetTenantFromToken` plug 能正确路由到对应租户。
  """
  def success(conn, _activity, %SuperAdmin{} = admin, _token) do
    # SuperAdmin 通常不走这个回调——它走 super_admin_sign_in/2。
    # 但万一走到这里，仍然发超管 token。
    issue_token(conn, admin.id, "public", "super_admin")
  end

  def success(conn, _activity, user, _token) do
    # 租户用户：Phase 3 后默认在 tenant_default schema
    role = user_role(user)
    tenant = user_tenant()
    issue_token(conn, user.id, tenant, role)
  end

  defp issue_token(conn, user_id, tenant, role) do
    case AuthToken.generate(user_id, %{"tenant" => tenant, "role" => role}) do
      {:ok, token, _claims} ->
        conn
        |> put_status(200)
        |> json(%{
          authentication: %{
            status: :success,
            bearer: token,
            tenant: tenant,
            role: role
          }
        })

      {:error, reason} ->
        Logger.error("Failed to issue auth token: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: "token_generation_failed"})
    end
  end

  defp user_role(%{role: role}) when is_atom(role), do: Atom.to_string(role)
  defp user_role(_), do: "student"

  # Phase 3：现有 User 都在 tenant_default schema。Phase 4 会从连接里读
  # organization_slug，为每个租户生成对应 tenant_<slug>。
  defp user_tenant() do
    # TODO Phase 4: 从 conn.assigns.organization_slug 读 slug
    "tenant_default"
  end

  @doc """
  Called when authentication fails.
  """
  def failure(conn, _activity, reason) do
    conn
    |> put_status(401)
    |> json(%{
      authentication: %{
        status: :failed,
        reason: reason_to_string(reason)
      }
    })
  end

  @doc """
  超管登录入口（不走 AshAuthentication 标准 flow）。

  入参：`%{"identity" => ..., "password" => ...}`（`identity` 为邮箱或
  用户名；旧版 `"email"` 键仍兼容）
  出参：成功返回 `{token, admin}`，失败返回 401。
  """
  def super_admin_sign_in(conn, %{"password" => password} = params) do
    identity = params["identity"] || params["email"]

    if is_binary(identity) do
      input =
        Ash.ActionInput.for_action(
          SuperAdmin,
          :sign_in_with_password,
          %{identity: identity, password: password}
        )

      case Ash.run_action(input, authorize?: false) do
        {:ok, %{admin: admin, token: token}} ->
          conn
          |> put_status(200)
          |> json(%{
            authentication: %{
              status: :success,
              bearer: token,
              tenant: "public",
              role: "super_admin",
              admin: %{
                id: admin.id,
                email: admin.email,
                name: admin.name
              }
            }
          })

        {:error, err} when is_struct(err) ->
          # 检查是不是 invalid_credentials 错误（Action 返回的 :invalid_credentials 被 Ash 包装为 UnknownError）
          if inspect(err) =~ "invalid_credentials" do
            conn
            |> put_status(401)
            |> json(%{
              authentication: %{
                status: :failed,
                reason: "invalid_credentials"
              }
            })
          else
            Logger.error("super_admin_sign_in failed: #{inspect(err)}")

            conn
            |> put_status(500)
            |> json(%{error: "internal_error"})
          end

        {:error, reason} ->
          Logger.error("super_admin_sign_in failed: #{inspect(reason)}")

          conn
          |> put_status(500)
          |> json(%{error: "internal_error"})
      end
    else
      conn
      |> put_status(400)
      |> json(%{error: "missing_email_or_password"})
    end
  end

  def super_admin_sign_in(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "missing_email_or_password"})
  end

  @doc """
  Called on sign-out. Revokes the current bearer token.
  """
  def sign_out(conn, _params) do
    conn
    |> AshAuthentication.Plug.Helpers.revoke_bearer_tokens(:tcm_edu)
    |> json(%{status: :ok})
  end

  @doc """
  Returns the authenticated user's profile (email, role, id, tenant).
  Requires a valid Bearer token.
  """
  def me(conn, _params) do
    # 三个可能位置（顺序：assigns.current_user、private.ash_actor、private.ash.actor）
    user =
      Map.get(conn.assigns, :current_user) ||
        conn.private[:ash_actor] ||
        get_in(conn.private, [:ash, :actor])

    tenant =
      conn.private[:ash_tenant] ||
        get_in(conn.private, [:ash, :tenant]) ||
        "public"

    role = conn.private[:tcm_edu_role]

    if user do
      body =
        %{id: user.id, email: user.email, tenant: tenant} |> maybe_put_role(role, user)

      conn
      |> put_status(200)
      |> json(%{data: body})
    else
      conn
      |> put_status(401)
      |> json(%{error: "Not authenticated"})
    end
  end

  defp maybe_put_role(body, role, _user) when is_binary(role) do
    Map.put(body, :role, role)
  end

  defp maybe_put_role(body, _role, %{role: role}) when is_atom(role) do
    Map.put(body, :role, Atom.to_string(role))
  end

  defp maybe_put_role(body, _role, _user), do: body

  @doc """
  Returns the effective permissions for any user by ID (admin only).
  """
  def user_permissions(conn, %{"user_id" => user_id}) do
    actor = Map.get(conn.assigns, :current_user)

    if actor && actor.role == :admin do
      permissions = TcmEdu.Accounts.effective_permissions(user_id)

      conn
      |> put_status(200)
      |> json(%{data: %{user_id: user_id, permissions: permissions}})
    else
      conn
      |> put_status(403)
      |> json(%{error: "Forbidden"})
    end
  end

  defp reason_to_string(reason) when is_binary(reason), do: reason
  defp reason_to_string(reason), do: inspect(reason)
end
