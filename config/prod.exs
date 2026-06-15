import Config

# Note: We intentionally skip force_ssl here so that running `MIX_ENV=prod
# mix phx.server` locally serves both Next.js static assets and the RPC
# endpoint over plain HTTP for end-to-end verification.
# Re-enable force_ssl in real deployments.
# config :ash_ts_demo, AshTsDemoWeb.Endpoint,
#   force_ssl: [
#     rewrite_on: [:x_forwarded_proto],
#     exclude: [
#       hosts: ["localhost", "127.0.0.1"]
#     ]
#   ]

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
