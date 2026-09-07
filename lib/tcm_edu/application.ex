defmodule TcmEdu.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = base_children() ++ optional_children()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TcmEdu.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp base_children do
    [
      TcmEduWeb.Telemetry,
      TcmEdu.Repo,
      {DNSCluster, query: Application.get_env(:tcm_edu, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TcmEdu.PubSub},
      {AshAuthentication.Supervisor, otp_app: :tcm_edu},
      # Oban background job processor — must start after the Repo
      {Oban, Application.fetch_env!(:tcm_edu, Oban)},
      # Start a worker by calling: TcmEdu.Worker.start_link(arg)
      # {TcmEdu.Worker, arg},
      # Jido agent runtime
      TcmEdu.Jido,
      # Start to serve requests, typically the last entry
      TcmEduWeb.Endpoint
    ]
  end

  defp optional_children do
    []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TcmEduWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
