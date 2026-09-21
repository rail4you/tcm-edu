defmodule TcmEdu.Repo do
  @moduledoc """
  Postgres-backed Repo used by both Ecto and AshPostgres.
  """

  use AshPostgres.Repo, otp_app: :tcm_edu

  @impl true
  def all_tenants do
    query = "SELECT nspname FROM pg_namespace WHERE nspname LIKE 'tenant_%' ORDER BY nspname"

    case __MODULE__.query(query) do
      {:ok, %{rows: rows}} -> Enum.map(rows, fn [name] -> name end)
      _ -> []
    end
  end

  @impl true
  def installed_extensions do
    # Enables citext, pg_trgm, vector, etc. if your resources need them. Keep the
    # ash-functions extension so AshPostgres' internal helpers are available.
    ["ash-functions", "citext", "vector"]
  end

  @impl true
  def min_pg_version do
    %Version{major: 13, minor: 0, patch: 0}
  end
end
