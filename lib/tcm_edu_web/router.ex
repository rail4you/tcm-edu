defmodule TcmEduWeb.Router do
  use TcmEduWeb, :router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers, only: [retrieve_from_bearer: 2, set_actor: 2]

  pipeline :api do
    plug :accepts, ["json"]

    plug TcmEduWeb.Plugs.SetTenantForSignIn

    plug CORSPlug,
      origin: [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://localhost:3001",
        "http://127.0.0.1:3001",
        "http://localhost:3002",
        "http://127.0.0.1:3002",
        "http://localhost:3003",
        "http://127.0.0.1:3003"
      ],
      methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
      credentials: true
  end

  # Pipeline for multipart file uploads (needs to accept multipart/form-data)
  pipeline :api_upload do
    plug :accepts, ["json", "multipart"]

    plug TcmEduWeb.Plugs.SetTenantForSignIn

    plug CORSPlug,
      origin: [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://localhost:3001",
        "http://127.0.0.1:3001",
        "http://localhost:3002",
        "http://127.0.0.1:3002",
        "http://localhost:3003",
        "http://127.0.0.1:3003"
      ],
      methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
      credentials: true

    plug :retrieve_from_bearer, :tcm_edu
    plug :set_actor, :user
  end

  pipeline :api_auth do
    plug :accepts, ["json"]

    plug CORSPlug,
      origin: [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://localhost:3001",
        "http://127.0.0.1:3001",
        "http://localhost:3002",
        "http://127.0.0.1:3002",
        "http://localhost:3003",
        "http://127.0.0.1:3003"
      ],
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

  # ── Chat / SSE endpoints ──────────────────────────────────────
  scope "/api", TcmEduWeb do
    pipe_through :api_auth

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

  # ── AI endpoints (lesson plan / image / mistake explain) ────────
  scope "/api/ai", TcmEduWeb do
    pipe_through :api_auth

    post "/lesson_plan", AIController, :lesson_plan
    post "/image", AIController, :image
    post "/mistake_explain", AIController, :mistake_explain
  end

  # ── Course static page ─────────────────────────────────────────────
  scope "/", TcmEduWeb do
    pipe_through :browser

    get "/course", FallbackController, :course
    get "/course/*path", FallbackController, :course
  end

  # ── Unified login (single entrance for all portals) ─────────────
  # The trigger-action form on LoginLive POSTs here; legacy per-portal
  # login URLs redirect here as well.
  scope "/", TcmEduWeb do
    pipe_through :browser

    post "/session", SessionController, :create
    post "/logout", SessionController, :delete
    get "/admin/login", SessionController, :legacy_login
    get "/teacher/login", SessionController, :legacy_login
  end

  # ── Admin panel (LiveView + daisyUI, session auth) ────────────────
  live_session :admin,
    on_mount: [{TcmEduWeb.AdminAuth, :ensure_admin}] do
    scope "/admin", TcmEduWeb do
      pipe_through :browser

      live "/", AdminDashboardLive, :index
      live "/users", AdminUsersLive, :index
      live "/knowledge", AdminKnowledgeLive, :index
    end
  end

  live_session :admin_super,
    on_mount: [{TcmEduWeb.AdminAuth, :ensure_super_admin}] do
    scope "/admin", TcmEduWeb do
      pipe_through :browser

      live "/tenants", AdminTenantsLive, :index
      live "/ai-dashboard", AdminAIDashboardLive, :index
      live "/ai-keys", AdminAIKeysLive, :index
    end
  end

  # ── Teacher file download (session auth checked in controller) ───
  scope "/teacher", TcmEduWeb do
    pipe_through :browser

    get "/quiz/template", QuizTemplateController, :template
  end

  # ── Teacher portal (LiveView + daisyUI, session auth) ─────────────
  live_session :teacher,
    on_mount: [{TcmEduWeb.TeacherAuth, :ensure_teacher}] do
    scope "/teacher", TcmEduWeb do
      pipe_through :browser

      live "/", TeacherDashboardLive, :index
      live "/courses", TeacherCoursesLive, :index
      live "/courses/new", TeacherCourseNewLive, :index
      live "/students", TeacherStudentsLive, :index
      live "/quiz", TeacherQuizLive, :index
      live "/ai/lesson-plan", TeacherAILessonLive, :index
      live "/ai/image", TeacherAIImageLive, :index
      live "/ai/quiz", TeacherAIQuizLive, :index
      live "/ai/jobs", TeacherAIJobsLive, :index
      live "/ai/knowledge", TeacherAIKnowledgeLive, :index
      live "/ai/chat", AiChatLive, :index
      live "/ai/simulated-patient", TeacherAISimulatedPatientLive, :index
      live "/mdt", TeacherMdtLive, :index
    end
  end

  # ── Student portal (LiveView storefront) ────────────────────────
  # Public pages work anonymously; learning pages require a student.
  live_session :student_public, on_mount: [{TcmEduWeb.StudentAuth, :fetch_student}] do
    scope "/", TcmEduWeb do
      pipe_through :browser

      live "/", StudentHomeLive, :index
      live "/login", LoginLive, :index
      live "/courses", StudentCoursesLive, :index
      live "/courses/:id", StudentCourseDetailLive, :index
    end
  end

  live_session :student, on_mount: [{TcmEduWeb.StudentAuth, :ensure_student}] do
    scope "/", TcmEduWeb do
      pipe_through :browser

      live "/learn", StudentLearnLive, :index
      live "/my-learning", StudentMyLearningLive, :index
      live "/my-learning/mistakes", StudentMistakesLive, :index
      live "/posts", StudentPostsLive, :index
      live "/posts/new", StudentPostNewLive, :index
      live "/chat", StudentChatLive, :index
      live "/ai-chat", AiChatLive, :index
      live "/notifications", StudentNotificationsLive, :index
      live "/simulated-patient", StudentSimulatedPatientLive, :index
      live "/simulated-patient/sessions/:id", StudentSimulatedPatientSessionLive, :index

      live "/simulated-patient/sessions/:id/evaluation",
           StudentSimulatedPatientSessionLive,
           :evaluation

      live "/simulated-patient/report", StudentClinicalReasoningReportLive, :index
      live "/mdt", StudentMdtLive, :index
      live "/mdt/rooms/:id", StudentMdtRoomLive, :index
    end
  end

  # ── SPA pages ─────────────────────────────────────────────────────
  scope "/", TcmEduWeb do
    pipe_through :browser

    live "/db", DbStatsLive, :index
  end
end
