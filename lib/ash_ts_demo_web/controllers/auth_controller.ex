defmodule AshTsDemoWeb.AuthController do
  @moduledoc """
  Authentication controller that handles password-based sign-in/sign-up
  and returns JSON responses with bearer tokens for the SPA client.
  """
  use AshTsDemoWeb, :controller
  use AshAuthentication.Phoenix.Controller

  @doc """
  Called on successful authentication (sign-in or registration).
  Returns a JSON response containing the bearer token.
  """
  def success(conn, _activity, _user, token) do
    conn
    |> put_status(200)
    |> json(%{
      authentication: %{
        status: :success,
        bearer: token
      }
    })
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
  Called on sign-out. Revokes the current bearer token.
  """
  def sign_out(conn, _params) do
    conn
    |> AshAuthentication.Plug.Helpers.revoke_bearer_tokens(:ash_ts_demo)
    |> json(%{status: :ok})
  end

  @doc """
  Returns the authenticated user's profile (email, role, id).
  Requires a valid Bearer token.
  """
  def me(conn, _params) do
    user = Map.get(conn.assigns, :current_user)

    if user do
      permissions = AshTsDemo.Accounts.effective_permissions(user.id)

      conn
      |> put_status(200)
      |> json(%{
        data: %{
          id: user.id,
          email: user.email,
          role: user.role,
          permissions: permissions
        }
      })
    else
      conn
      |> put_status(401)
      |> json(%{error: "Not authenticated"})
    end
  end

  @doc """
  Returns the effective permissions for any user by ID (admin only).
  """
  def user_permissions(conn, %{"user_id" => user_id}) do
    actor = Map.get(conn.assigns, :current_user)

    if actor && actor.role == :admin do
      permissions = AshTsDemo.Accounts.effective_permissions(user_id)

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
