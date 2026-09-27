defmodule TcmEdu.MixProject do
  use Mix.Project

  def project do
    [
      app: :tcm_edu,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      usage_rules: usage_rules()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {TcmEdu.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Allow lazy_html to override the elixir_make version that was pinned by
  # the lock file. Phoenix LiveView's test helpers require lazy_html, which
  # in turn requires elixir_make ~> 0.9.0. The mix.lock had 0.10.0
  # (transitively from picosat_elixir) and Hex refuses to downgrade
  # automatically.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        :elixir,
        :ash,
        ~r/^ash_/,
        :phoenix,
        ~r/^phoenix_/
      ],
      skills: [
        location: ".claude/skills",
        deps: [:jido],
        build: [
          "ash-framework": [
            description:
              "Use when working with Ash Framework or any Ash extension (ash_postgres, ash_authentication, etc). Always consult this for domain changes, resources, or Ash-related features.",
            usage_rules: [:ash, ~r/^ash_/]
          ],
          "phoenix-framework": [
            description:
              "Use when working with Phoenix web layer, LiveView, controllers, router, or any Phoenix-related code.",
            usage_rules: [:phoenix, ~r/^phoenix_/]
          ]
        ]
      ]
    ]
  end

  defp elixir_make_override do
    [{:elixir_make, "~> 0.9.0", override: true}]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_live_view, "~> 1.0"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      # Ash framework
      {:ash, "~> 3.0"},
      {:ash_postgres, "~> 2.0"},
      # Ash + Phoenix form/LiveView integration (AshPhoenix.Form, AshPhoenix.LiveView).
      # 已经是 ash_ai / ash_authentication_phoenix 的传递依赖,这里显式声明以便
      # 在 domain 上启用 `extensions: [AshPhoenix]` 并自动生成 form_to_<action>。
      {:ash_phoenix, "~> 2.3"},
      # SAT solver required by Ash.Policy.Authorizer
      {:picosat_elixir, "~> 0.2"},
      # Authentication
      {:ash_authentication, "~> 4.0"},
      {:ash_authentication_phoenix, "~> 2.0"},
      {:bcrypt_elixir, "~> 3.0"},
      # CORS support
      {:cors_plug, "~> 3.0"},
      # LiveView test helper (parses rendered HTML for assertions).
      {:lazy_html, ">= 0.1.0", only: :test},
      # Unified feature/e2e tests for LiveView + static pages.
      {:phoenix_test, "~> 0.12", only: :test},
      # xlsx template generation (teacher quiz import).
      {:elixlsx, "~> 0.6"},
      # xlsx parsing (teacher quiz import).
      {:xlsxir, "~> 1.6"},
      # Office/PDF document text extraction (tenant knowledge base ingestion).
      {:extractous_ex, "~> 0.2.1"},
      # Agent framework
      {:jido, "~> 2.0"},
      {:jido_ai, "~> 2.0"},
      {:jido_browser, "~> 2.0"},
      # AI vectorization (tenant knowledge RAG); pinned to 1.0.x to stay on ash 3.28
      {:ash_ai, "~> 1.0.0"},
      # Background jobs
      {:oban, "~> 2.18"},
      # File storage and attachments (not yet published to Hex)
      {:ash_storage, github: "ash-project/ash_storage"},
      # Dev tooling: AGENTS.md / skill management from deps
      {:usage_rules, "~> 1.1", only: [:dev]},
      {:igniter, "~> 0.6", only: [:dev]},
      # Tidewave MCP server for Phoenix (dev tooling: DB/EVAL/docs MCP tools).
      # NOTE: must NOT carry `only: [:dev]` or it propagates an `:only` restriction
      # onto `plug` that conflicts with ash_json_api's unrestricted plug dep.
      {:tidewave, "~> 0.9"}
    ] ++ elixir_make_override()
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup"],
      "ash.setup": ["ash.codegen --dev", "ash.migrate"],
      "assets.setup": ["cmd npm install --prefix assets"],
      "assets.build": ["cmd npm run build --prefix assets"],
      "assets.deploy": ["assets.build", "phx.digest"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      # NOTE: tcm_edu.migrate 确保 test 库也有 tenant_default schema + 租户表，
      # 否则 Phase 3 的多租户测试会报 relation "tenant_default.users" does not exist。
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "tcm_edu.migrate", "test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
