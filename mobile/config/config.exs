import Config

# Register the Repo so Mix tasks (mix ecto.create, mix ecto.migrate) can
# discover it. The actual database path is configured at runtime in
# TcmMobile.Repo.init/2 via the MOB_DATA_DIR environment variable.
config :tcm_mobile, ecto_repos: [TcmMobile.Repo]

# Wire the Repo into Mob.ScreenState so screens using `vsn:` get automatic
# state persistence. Remove this line to disable screen state persistence.
config :mob, :repo, TcmMobile.Repo

# Screen-state persistence migration is generated; run `mix ecto.migrate`
# locally if you need the repo tables outside a device build.
