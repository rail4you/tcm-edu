defmodule TcmEduWeb.Router do
  use TcmEduWeb, :router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers, only: [retrieve_from_bearer: 2, set_actor: 2]

  pipeline :api do
    plug :accepts, ["json"]

    plug TcmEduWeb.Plugs.SetTenantForSignIn

    plug CORSPlug,
      origin: ["http://localhost:3000", "http://127.0.0.1:3000", "http://localhost:3001", "http://127.0.0.1:3001", "http://localhost:3002", "http://127.0.0.1:3002", "http://localhost:3003", "http://127.0.0.1:3003"],
      methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
      credentials: true
  end

  # Pipeline for multipart file uploads (needs to accept multipart/form-data)
  pipeline :api_upload do
    plug :accepts, ["json", "multipart"]

    plug TcmEduWeb.Plugs.SetTenantForSignIn

    plug CORSPlug,
      origin: ["http://localhost:3000", "http://127.0.0.1:3000", "http://localhost:3001", "http://127.0.0.1:3001", "http://localhost:3002", "http://127.0.0.1:3002", "http://localhost:3003", "http://127.0.0.1:3003"],
      methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
      credentials: true

    plug :retrieve_from_bearer, :tcm_edu
    plug :set_actor, :user
  end

  pipeline :api_auth do
    plug :accepts, ["json"]

    plug CORSPlug,
      origin: ["http://localhost:3000", "http://127.0.0.1:3000", "http://localhost:3001", "http://127.0.0.1:3001", "http://localhost:3002", "http://127.0.0.1:3002", "http://localhost:3003", "http://127.0.0.1:3003"],
      methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
      credentials: true

    plug :retrieve_from_bearer, :tcm_edu
    plug :set_actor, :user
    plug TcmEduWeb.Plugs.SetTenantFromToken
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_root_layout, html: {TcmEduWeb.Layouts, :root}
    plug :put_secure_browser_headers
  end

  # ── Current user endpoint (requires Bearer token) ─────────────────
  # Must be defined BEFORE auth_routes since auth_routes uses forward
  # which would swallow /me.
  scope "/api/auth", TcmEduWeb do
    pipe_through :api_auth

    get "/me", AuthController, :me
    get "/users/:user_id/permissions", AuthController, :user_permissions
  end

  # ── Auth routes (sign-in, register, sign-out via POST) ────────────
  scope "/api/auth", TcmEduWeb do
    pipe_through :api

    # Sign-out must be defined BEFORE auth_routes, because auth_routes
    # forwards "*" via StrategyRouter which would otherwise swallow it.
    post "/sign_out", AuthController, :sign_out

    # SuperAdmin login (custom action — separate from AshAuthentication flow)
    match :options, "/super_admin_sign_in", AuthController, :options
    post "/super_admin_sign_in", AuthController, :super_admin_sign_in

    auth_routes(AuthController, TcmEdu.Accounts.User, path: "/")
  end

  # ── JSON RPC surface exposed by AshTypescript ──────────────────────
  # Uses the authenticated pipeline so Ash policies can check the actor.
  scope "/api", TcmEduWeb do
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

  # ── File upload endpoint (multipart, authenticated via Bearer) ────
  scope "/api", TcmEduWeb do
    pipe_through :api_upload

    match :options, "/posts/:post_id/upload/:attachment_name", PostUploadController, :options
    post "/posts/:post_id/upload/:attachment_name", PostUploadController, :upload
  end

  # ── Admin panel (LiveView + daisyUI, session auth) ────────────────
  # Login POST target for the trigger-action form on AdminLoginLive.
  scope "/admin", TcmEduWeb do
    pipe_through :browser

    post "/session", AdminSessionController, :create
    post "/logout", AdminSessionController, :delete
  end

  live_session :admin_public do
    scope "/admin", TcmEduWeb do
      pipe_through :browser

      live "/login", AdminLoginLive, :index
    end
  end

  live_session :admin,
    on_mount: [{TcmEduWeb.AdminAuth, :ensure_admin}] do
    scope "/admin", TcmEduWeb do
      pipe_through :browser

      live "/", AdminDashboardLive, :index
      live "/users", AdminUsersLive, :index
    end
  end

  live_session :admin_super,
    on_mount: [{TcmEduWeb.AdminAuth, :ensure_super_admin}] do
    scope "/admin", TcmEduWeb do
      pipe_through :browser

      live "/tenants", AdminTenantsLive, :index
    end
  end

  # ── Teacher portal (LiveView + daisyUI, session auth) ─────────────
  scope "/teacher", TcmEduWeb do
    pipe_through :browser

    post "/session", TeacherSessionController, :create
    post "/logout", TeacherSessionController, :delete
  end

  live_session :teacher_public do
    scope "/teacher", TcmEduWeb do
      pipe_through :browser

      live "/login", TeacherLoginLive, :index
    end
  end

  live_session :teacher,
    on_mount: [{TcmEduWeb.TeacherAuth, :ensure_teacher}] do
    scope "/teacher", TcmEduWeb do
      pipe_through :browser

      live "/", TeacherDashboardLive, :index
      live "/courses", TeacherCoursesLive, :index
      live "/courses/new", TeacherCourseNewLive, :index
      live "/courses/:id/edit", TeacherCourseEditLive, :index
      live "/students", TeacherStudentsLive, :index
    end
  end

  # ── Course static page ─────────────────────────────────────────────
  scope "/", TcmEduWeb do
    pipe_through :browser

    get "/course", FallbackController, :course
    get "/course/*path", FallbackController, :course
  end

  # ── SPA pages ─────────────────────────────────────────────────────
  scope "/", TcmEduWeb do
    pipe_through :browser

    live "/db", DbStatsLive, :index

    get "/", FallbackController, :root
    get "/posts", FallbackController, :spa
    get "/posts/new", FallbackController, :spa
    # 学生端 Phase 9 新增的静态路由（生产静态导出 + dev 直连都可达）
    get "/courses", FallbackController, :spa
    get "/course", FallbackController, :spa
    get "/learn", FallbackController, :spa
    get "/my-learning", FallbackController, :spa
    get "/login", FallbackController, :spa
    get "/app", FallbackController, :app
    get "/app/*path", FallbackController, :app
  end
end
