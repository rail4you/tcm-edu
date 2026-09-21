defmodule TcmEdu.Repo.TenantMigrations.FixQuestionOptions do
  @moduledoc """
  Align `questions.options` with the resource type `{:array, :map}`.

  This file was generated with `mix ash_postgres.generate_migrations
  fix_question_options` and then audited: the generator emitted full
  `CREATE TABLE` statements for all tenant tables (they have no snapshots
  yet — see `priv/resource_snapshots/repo/tenants/`, which this run
  baselined), but every one of those tables already exists in all tenant
  schemas, so only the true delta is kept here:

    * `questions.options`: `jsonb` → `jsonb[]`

  The drift came from the hand-written
  `20260901000001_create_tenant_quiz_and_notifications` migration, which
  declared the column as plain `jsonb`. Creates/reads happened to
  round-trip, but any UPDATE touching `options` fails in Postgres with
  `cannot cast type jsonb to jsonb[]`.

  Existing rows store JSON arrays and are converted element-wise; anything
  else falls back to an empty array.

  NOTE: raw SQL below is explicitly schema-qualified with `prefix()`.
  `Ecto.Migrator.run(..., prefix: schema)` qualifies Ecto DSL operations
  but NOT raw `execute/1` strings — an unqualified statement would land on
  `public.questions` instead of `<tenant>.questions`.
  """

  use Ecto.Migration

  def up do
    execute("ALTER TABLE \"#{prefix()}\".questions ALTER COLUMN options DROP DEFAULT")
    execute("ALTER TABLE \"#{prefix()}\".questions ADD COLUMN options_arr jsonb[]")

    execute("""
    UPDATE \"#{prefix()}\".questions
    SET options_arr = COALESCE(
      (SELECT array_agg(e) FROM jsonb_array_elements(
        CASE WHEN jsonb_typeof(options) = 'array' THEN options ELSE '[]' END
      ) AS e),
      '{}'::jsonb[]
    )
    """)

    execute("ALTER TABLE \"#{prefix()}\".questions DROP COLUMN options")
    execute("ALTER TABLE \"#{prefix()}\".questions RENAME COLUMN options_arr TO options")
    execute("ALTER TABLE \"#{prefix()}\".questions ALTER COLUMN options SET DEFAULT '{}'")
    execute("ALTER TABLE \"#{prefix()}\".questions ALTER COLUMN options SET NOT NULL")
  end

  def down do
    execute("ALTER TABLE \"#{prefix()}\".questions ALTER COLUMN options DROP DEFAULT")
    execute("ALTER TABLE \"#{prefix()}\".questions ADD COLUMN options_json jsonb")

    execute("UPDATE \"#{prefix()}\".questions SET options_json = to_jsonb(options)")

    execute("ALTER TABLE \"#{prefix()}\".questions DROP COLUMN options")
    execute("ALTER TABLE \"#{prefix()}\".questions RENAME COLUMN options_json TO options")
    execute("ALTER TABLE \"#{prefix()}\".questions ALTER COLUMN options SET DEFAULT '[]'")
    execute("ALTER TABLE \"#{prefix()}\".questions ALTER COLUMN options SET NOT NULL")
  end
end
