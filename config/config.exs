# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :tcm_edu,
  ecto_repos: [TcmEdu.Repo],
  generators: [timestamp_type: :utc_datetime]

# Ash framework — list all domains so codegen and CLI tools can find them.
config :tcm_edu,
  ash_domains: [
    TcmEdu.System,
    TcmEdu.TodoDomain,
    TcmEdu.Accounts,
    TcmEdu.Courses,
    TcmEdu.ChatDomain,
    TcmEdu.PostDomain,
    TcmEdu.Storage
  ],
  # Storage: local Disk service for file uploads
  storage_root: "priv/storage",
  token_signing_secret: "dev-secret-change-in-production-PLEASE-CHANGE-ME",
  # Tenant migrations path (used by TcmEdu.TenantProvisioning)
  tenant_migrations_path: "priv/repo/tenant_migrations"

# AshTypescript codegen config. Output is written into the shared workspace
# package `frontend-monorepo/packages/rpc-client/src/` so the student, admin
# and teacher apps all import the same generated client via `@tcm-edu/rpc-client`.
config :ash_typescript,
  output_file: "frontend-monorepo/packages/rpc-client/src/ash_rpc.ts",
  types_output_file: "frontend-monorepo/packages/rpc-client/src/ash_types.ts",
  zod_output_file: "frontend-monorepo/packages/rpc-client/src/ash_zod.ts",
  generate_zod_schemas: true,
  zod_import_path: "zod",
  zod_schema_suffix: "Schema",
  output_field_formatter: :camel_case,
  input_field_formatter: :camel_case,
  run_endpoint: "/api/rpc/run",
  validate_endpoint: "/api/rpc/validate",
  # Lifecycle hooks: inject Bearer token from localStorage into every RPC request
  rpc_action_before_request_hook: "RpcHooks.beforeRequest",
  rpc_action_after_request_hook: "RpcHooks.afterRequest",
  rpc_action_hook_context_type: "RpcHooks.ActionHookContext",
  import_into_generated: [
    %{
      import_name: "RpcHooks",
      file: "frontend-monorepo/packages/rpc-client/src/rpcHooks.ts"
    }
  ]

# Configure the endpoint
config :tcm_edu, TcmEduWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: TcmEduWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TcmEdu.PubSub,
  live_view: [signing_salt: "tbUPJBUE"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Jido agent runtime configuration
config :tcm_edu, TcmEdu.Jido,
  max_tasks: 1000,
  agent_pools: []

# Jido AI — model aliases map short names to provider:model-id
config :jido_ai,
  react_token_secret:
    System.get_env("REACT_TOKEN_SECRET", "tcm-edu-local-react-token-secret-32b"),
  model_aliases: %{
    fast: "deepseek:deepseek-chat",
    minimax: "minimax:abab6.5s-chat"
  }

# ReqLLM — HTTP client for LLM APIs, auto-loads .env for API keys
config :req_llm,
  load_dotenv: true,
  receive_timeout: 120_000

# AshAuthentication endpoint for token audience claims
config :ash_authentication,
  ash_authentication: [
    strategies: [
      password: [
        sign_in_token_lifetime: 60 * 60 * 24 * 30
      ]
    ]
  ]

# Oban — background job processing. Uses the same PostgreSQL database as the
# Ash Repo. The default queue is `:default` and jobs are inserted with
# Oban.insert/1 in the chat controller.
config :tcm_edu, Oban,
  repo: TcmEdu.Repo,
  engine: Oban.Engines.Basic,
  queues: [default: 5],
  plugins: []

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
