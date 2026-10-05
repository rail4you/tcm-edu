ExUnit.start()

# The app's screen-state persistence repo + the student Store singleton.
# Started once for the whole suite (they are globally named processes).
{:ok, _} = Application.ensure_all_started(:ecto_sqlite3)
{:ok, _} = TcmMobile.Repo.start_link()
{:ok, _} = TcmMobile.Store.start_link()

Ecto.Migrator.with_repo(TcmMobile.Repo, fn repo ->
  Ecto.Migrator.run(repo, Application.app_dir(:tcm_mobile, "priv/repo/migrations"), :up,
    all: true
  )
end)
