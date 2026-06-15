# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ash_ts_demo,
  ecto_repos: [AshTsDemo.Repo],
  generators: [timestamp_type: :utc_datetime]

# Ash framework — list all domains so codegen and CLI tools can find them.
config :ash_ts_demo,
  ash_domains: [AshTsDemo.TodoDomain, AshTsDemo.Accounts, AshTsDemo.ChatDomain],
  token_signing_secret: "dev-secret-change-in-production-PLEASE-CHANGE-ME"

# AshTypescript codegen config. Output is written into the Next.js project
# under frontend/lib/generated/ so the frontend can directly import the
# generated client.
config :ash_typescript,
  output_file: "frontend/lib/generated/ash_rpc.ts",
  types_output_file: "frontend/lib/generated/ash_types.ts",
  zod_output_file: "frontend/lib/generated/ash_zod.ts",
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
      file: "frontend/lib/rpcHooks.ts"
    }
  ]

# Configure the endpoint
config :ash_ts_demo, AshTsDemoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: AshTsDemoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AshTsDemo.PubSub,
  live_view: [signing_salt: "tbUPJBUE"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Jido agent runtime configuration
config :ash_ts_demo, AshTsDemo.Jido,
  max_tasks: 1000,
  agent_pools: []

# Jido AI — model aliases map short names to provider:model-id
config :jido_ai,
  react_token_secret:
    System.get_env("REACT_TOKEN_SECRET", "ash-ts-demo-local-react-token-secret-32b"),
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

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
