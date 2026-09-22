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

# Postgrex type set including the AshPostgres vector extension (pgvector).
config :tcm_edu, TcmEdu.Repo, types: TcmEdu.PostgrexTypes

# AshStorage：所有上传走 `xingningshu` OSS bucket（阶段一部署前提）
config :tcm_edu,
  storage: [
    service: {TcmEdu.Storage.OSS.Service, []}
  ]

# Ash framework — list all domains so codegen and CLI tools can find them.
config :tcm_edu,
  ash_domains: [
    TcmEdu.System,
    TcmEdu.TodoDomain,
    TcmEdu.Accounts,
    TcmEdu.Courses,
    TcmEdu.Enrollment,
    TcmEdu.ChatDomain,
    TcmEdu.PostDomain,
    TcmEdu.Quiz,
    TcmEdu.Notification,
    TcmEdu.Storage,
    TcmEdu.Knowledge,
    TcmEdu.SimulatedPatient
  ],
  # Storage: local Disk service for file uploads
  storage_root: "priv/storage",
  token_signing_secret: "dev-secret-change-in-production-PLEASE-CHANGE-ME",
  # Tenant migrations path (used by TcmEdu.TenantProvisioning)
  tenant_migrations_path: "priv/repo/tenant_migrations"

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
# 参考 KnowledgeHub：text=qwen-flash / vision=qwen3-vl-flash / plus=qwen-plus，
# 均走 req_llm 内置 `:alibaba_cn`（DashScope OpenAI 兼容）。
config :jido_ai,
  react_token_secret:
    System.get_env("REACT_TOKEN_SECRET", "tcm-edu-local-react-token-secret-32b"),
  model_aliases: %{
    # 默认聊天走 qwen-flash（DashScope 有余额，参考 KnowledgeHub）
    fast: "alibaba_cn:qwen-flash",
    deepseek: "deepseek:deepseek-chat",
    minimax: "minimax:abab6.5s-chat",
    qwen: "alibaba_cn:qwen-flash",
    qwen_flash: "alibaba_cn:qwen-flash",
    qwen_plus: "alibaba_cn:qwen-plus",
    qwen_vl: "alibaba_cn:qwen3-vl-flash"
  }

# TcmEdu AI — 直接对接 DashScope OpenAI 兼容接口（Req 实现，参考 KnowledgeHub）
config :tcm_edu, TcmEdu.AI,
  base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
  text_model: "qwen-flash",
  vision_model: "qwen3-vl-flash",
  plus_model: "qwen-plus",
  image_model: "wanx2.1-t2i-turbo",
  image_base_url: "https://dashscope.aliyuncs.com/api/v1",
  timeout: 60_000

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
