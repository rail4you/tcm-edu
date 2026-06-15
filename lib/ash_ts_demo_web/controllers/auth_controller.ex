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

  defp reason_to_string(reason) when is_binary(reason), do: reason
  defp reason_to_string(reason), do: inspect(reason)
end
