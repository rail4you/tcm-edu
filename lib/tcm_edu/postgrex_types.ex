# Postgrex type set for TcmEdu.Repo.
#
# Includes `AshPostgres.Extensions.Vector` so pgvector (`vector` columns, cosine
# distance operators) works in Ecto/Ash queries. Referenced via the repo's
# `types` config.
#
# NOTE: `Postgrex.Types.define/3` defines the module itself, so this file must
# NOT wrap it in a `defmodule` block.

Postgrex.Types.define(
  TcmEdu.PostgrexTypes,
  [AshPostgres.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  []
)
