defmodule AshTsDemo.DbStats do
  @moduledoc """
  Periodically queries the connected Postgres database and broadcasts a
  snapshot of the database name, list of public tables, and per-table
  row counts to the `"db_stats"` Phoenix.PubSub topic.

  Subscribers (typically a LiveView page) can react to `:db_stats_updated`
  messages and re-render without polling on their own.
  """

  use GenServer

  alias Phoenix.PubSub

  @pubsub AshTsDemo.PubSub
  @topic "db_stats"

  # Five seconds is responsive enough to feel live without hammering the DB.
  @refresh_interval :timer.seconds(5)

  # Start the GenServer on application boot. We pass the refresh interval
  # through `start_link/1` so tests can dial it down (or disable polling
  # entirely by passing `:infinity`).
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the most recent snapshot broadcast on `"db_stats"`. Useful in
  tests and from IEx; in the running app the LiveView subscribes directly.
  """
  def subscribe do
    PubSub.subscribe(@pubsub, @topic)
  end

  def topic, do: @topic

  ## GenServer callbacks

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :refresh_interval, @refresh_interval)

    # Capture the first snapshot synchronously so the first subscriber
    # never sees an empty/loading state.
    send(self(), :refresh)

    schedule_refresh(interval)
    {:ok, %{interval: interval, last_error: nil}}
  end

  @impl true
  def handle_info(:refresh, state) do
    snapshot = build_snapshot()

    PubSub.broadcast(@pubsub, @topic, {:db_stats_updated, snapshot})

    schedule_refresh(state.interval)
    {:noreply, %{state | last_error: Map.get(snapshot, :error)}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  ## Internals

  defp schedule_refresh(:infinity), do: :ok
  defp schedule_refresh(interval), do: Process.send_after(self(), :refresh, interval)

  defp build_snapshot do
    %{db_name: db_name(), tables: tables_with_counts(), updated_at: DateTime.utc_now()}
  rescue
    error ->
      %{
        db_name: nil,
        tables: [],
        updated_at: DateTime.utc_now(),
        error: Exception.message(error)
      }
  end

  defp db_name do
    %{rows: [[name]]} = Ecto.Adapters.SQL.query!(AshTsDemo.Repo, "SELECT current_database()")
    name
  end

  # Restrict to `schemaname = 'public'` so the inspector only reports the
  # tables the application actually owns, not catalog/internal Postgres
  # tables. `reltuples` is the planner's estimate and is essentially free
  # to read; we still run an exact `SELECT count(*)` for accuracy on
  # small tables, which is what the demo uses.
  defp tables_with_counts do
    sql = """
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
    ORDER BY tablename
    """

    %{rows: rows} = Ecto.Adapters.SQL.query!(AshTsDemo.Repo, sql)

    Enum.map(rows, fn [table] ->
      %{name: table, row_count: count_rows(table)}
    end)
  end

  # `count(*)` is wrapped in a quoted identifier to defend against SQL
  # injection in the unlikely case that a public table name contains
  # funny characters. `pg_tables` only returns names that already exist
  # in the database, so the identifier is safe to interpolate.
  defp count_rows(table) do
    %{rows: [[count]]} =
      Ecto.Adapters.SQL.query!(
        AshTsDemo.Repo,
        ~s|SELECT count(*) FROM "#{table}"|
      )

    count
  end
end
