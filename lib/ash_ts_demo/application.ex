defmodule AshTsDemo.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = base_children() ++ optional_children()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AshTsDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp base_children do
    [
      AshTsDemoWeb.Telemetry,
      AshTsDemo.Repo,
      {DNSCluster, query: Application.get_env(:ash_ts_demo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AshTsDemo.PubSub},
      {AshAuthentication.Supervisor, otp_app: :ash_ts_demo},
      # Oban background job processor — must start after the Repo
      {Oban, Application.fetch_env!(:ash_ts_demo, Oban)},
      # Start a worker by calling: AshTsDemo.Worker.start_link(arg)
      # {AshTsDemo.Worker, arg},
      # Jido agent runtime
      AshTsDemo.Jido,
      # Start to serve requests, typically the last entry
      AshTsDemoWeb.Endpoint
    ]
  end

  defp optional_children do
    []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AshTsDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
