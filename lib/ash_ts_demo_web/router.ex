defmodule AshTsDemoWeb.Router do
  use AshTsDemoWeb, :router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers, only: [retrieve_from_bearer: 2, set_actor: 2]

  pipeline :api do
    plug :accepts, ["json"]

    plug CORSPlug,
      origin: ["http://localhost:3000", "http://127.0.0.1:3000"],
      methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
      credentials: true
  end

  pipeline :api_auth do
    plug :accepts, ["json"]

    plug CORSPlug,
      origin: ["http://localhost:3000", "http://127.0.0.1:3000"],
      methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
      credentials: true

    plug :retrieve_from_bearer, :ash_ts_demo
    plug :set_actor, :user
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_root_layout, html: {AshTsDemoWeb.Layouts, :root}
    plug :put_secure_browser_headers
  end

  # ── Auth routes (sign-in, register, sign-out via POST) ────────────
  scope "/api/auth", AshTsDemoWeb do
    pipe_through :api

    # Sign-out must be defined BEFORE auth_routes, because auth_routes
    # forwards "*" via StrategyRouter which would otherwise swallow it.
    post "/sign_out", AuthController, :sign_out

    auth_routes(AuthController, AshTsDemo.Accounts.User, path: "/")
  end

  # ── JSON RPC surface exposed by AshTypescript ──────────────────────
  # Uses the authenticated pipeline so Ash policies can check the actor.
  scope "/api", AshTsDemoWeb do
    pipe_through :api_auth

    match :options, "/rpc/run", AshTypescriptRpcController, :run
    match :options, "/rpc/validate", AshTypescriptRpcController, :validate

    post "/rpc/run", AshTypescriptRpcController, :run
    post "/rpc/validate", AshTypescriptRpcController, :validate

    # Chat endpoint — SSE streaming responses from AI agents
    match :options, "/chat", ChatController, :options
    post "/chat", ChatController, :chat

    # SSE stream of long-running task lifecycle events for the current user.
    # The explicit `match :options` route is required so the CORS preflight
    # actually reaches the `:api_auth` pipeline (where CORSPlug lives) instead
    # of falling through to NoRouteError.
    match :options, "/chat/events", ChatController, :options
    get "/chat/events", ChatEventsController, :subscribe
  end

  # ── SPA fallback ───────────────────────────────────────────────────
  scope "/", AshTsDemoWeb do
    pipe_through :browser

    live "/db", DbStatsLive, :index

    get "/", FallbackController, :root
    get "/app", FallbackController, :app
    get "/app/*path", FallbackController, :app
  end
end
