import Config

# Register the Repo so Mix tasks (mix ecto.create, mix ecto.migrate) can
# discover it. The actual database path is configured at runtime in
# TcmMobile.Repo.init/2 via the MOB_DATA_DIR environment variable.
config :tcm_mobile, ecto_repos: [TcmMobile.Repo]

# Wire the Repo into Mob.ScreenState so screens using `vsn:` get automatic
# state persistence. Remove this line to disable screen state persistence.
config :mob, :repo, TcmMobile.Repo

# ── 后端对接 ──────────────────────────────────────────────────────────────────
# api_source: :remote → 登录 / 身份走本地 Phoenix API；:local → 纯离线演示数据。
#           测试固定 :local，保证用例不碰网络。
# api_url   : Android 模拟器靠 `adb reverse tcp:4011 tcp:4011` 访问宿主机，
#            所以地址用 127.0.0.1（App 的 network_security_config 已放行明文）。
# api_org_slug: 登录时告诉后端用哪个租户；nil 则回退 tenant_default。
config :tcm_mobile,
  api_source: if(config_env() == :test, do: :local, else: :remote),
  api_url: "http://127.0.0.1:4011/api",
  api_org_slug: "gzu"

# Screen-state persistence migration is generated; run `mix ecto.migrate`
# locally if you need the repo tables outside a device build.
