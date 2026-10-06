defmodule TcmEduWeb.Plugs.RequireAuth do
  @moduledoc """
  未认证则 401 并 `halt` —— 给 `forward` 进来的 AshJsonApi 路由用。

  `:api_auth` 管道里的 `retrieve_from_bearer` / `set_actor` **不 halt**，它们只
  设置 assigns，由各 controller 自己判断（`AuthController.me/2` 就是这么做的）。
  AshJsonApi 的 controller 不做这个判断，会拿着 nil actor 跑 read action，撞上
  `Ash.Error.Query.ReadActionRequiresActor` 被包装成 HTTP 400，而不是 401。

  这里复用与 `AuthController.me/2` 完全相同的三个取值位置，保证返回体一致：
  `{"error": "Not authenticated"}`。
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if actor(conn) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(401, Jason.encode!(%{error: "Not authenticated"}))
      |> halt()
    end
  end

  defp actor(conn) do
    conn.assigns[:current_user] ||
      conn.private[:ash_actor] ||
      get_in(conn.private, [:ash, :actor])
  end
end
