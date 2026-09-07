import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/tcm_edu start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :tcm_edu, TcmEduWeb.Endpoint, server: true
end

config :tcm_edu, TcmEduWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4011"))]

if config_env() == :prod do
  # Database configuration with sensible defaults for local Postgres.
  # Override individual env vars or set DATABASE_URL for full control.
  database_url = System.get_env("DATABASE_URL")

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  if database_url do
    config :tcm_edu, TcmEdu.Repo,
      url: database_url,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
      socket_options: maybe_ipv6
  else
    config :tcm_edu, TcmEdu.Repo,
      username: System.get_env("PGUSER", "postgres"),
      password: System.get_env("PGPASSWORD", "postgres"),
      hostname: System.get_env("PGHOST", "localhost"),
      port: String.to_integer(System.get_env("PGPORT", "5433")),
      database: System.get_env("PGDATABASE", "postgres"),
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
      socket_options: maybe_ipv6
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      "tcm_edu_default_secret_key_base_replace_in_real_prod_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

  host = System.get_env("PHX_HOST") || "localhost"

  config :tcm_edu, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :tcm_edu, TcmEduWeb.Endpoint,
    url: [host: host, port: String.to_integer(System.get_env("PORT", "4011"))],
    http: [
      ip: {0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT", "4011"))
    ],
    secret_key_base: secret_key_base

  config :tcm_edu,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") ||
        "prod-secret-change-me-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
end
