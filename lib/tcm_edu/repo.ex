defmodule TcmEdu.Repo do
  @moduledoc """
  Postgres-backed Repo used by both Ecto and AshPostgres.
  """

  use AshPostgres.Repo, otp_app: :tcm_edu

  @impl true
  def installed_extensions do
    # Enables citext, pg_trgm, etc. if your resources need them. Keep the
    # ash-functions extension so AshPostgres' internal helpers are available.
    ["ash-functions", "citext"]
  end

  @impl true
  def min_pg_version do
    %Version{major: 13, minor: 0, patch: 0}
  end
end
