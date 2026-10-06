defmodule TcmMobile.MixProject do
  use Mix.Project

  def project do
    [
      app: :tcm_mobile,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: false,
      deps: deps(),
      aliases: aliases(),
      erlc_paths: ["src"],
      erlc_options: [:debug_info]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:mob, "~> 0.9.12"},
      {:mob_dev, "~> 0.7.12", only: :dev, runtime: false},
      {:ecto_sqlite3, "~> 0.18"},
      # HTTP client for the optional remote API backend (see TcmMobile.Api).
      # Mob's on-device BEAM uses the same Req stack as the Phoenix backend,
      # so a client written here transfers 1:1 once the server exposes a JSON API.
      {:req, "~> 0.5"},
      # req 把 plug 当可选依赖：不显式声明的话 req 编译时 `Code.ensure_loaded?(Plug)`
      # 为 false，会编进"missing plug dependency"的桩，Req.Test / Req.Plug 全不可用。
      {:plug, "~> 1.0"},
      # Code quality — Credo + ex_slop (catches AI-generated patterns
      # like blanket rescue, narrator docs, redundant Enum chains, etc).
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.2", only: [:dev, :test], runtime: false}
    ]
  end

  # Shorthands for the common mob workflows — `mix deploy` is `mix mob.deploy`,
  # etc. Extra args pass through to the underlying task, so `mix deploy
  # --device <udid>` works as expected.
  defp aliases do
    [
      connect: ["mob.connect"],
      deploy: ["mob.deploy"],
      watch: ["mob.watch"],
      icon: ["mob.icon"],
      ios: ["mob.deploy --ios"],
      "ios.native": ["mob.deploy --native --ios"]
    ]
  end
end
