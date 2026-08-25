defmodule Hologram.Migration.ApplyTest do
  # One node, a virgin database, the whole chain - and what a second run finds when the
  # chain is already there. The happy path the other suites of this tier start from and
  # then perturb: they plant a prefix, kill a build, or race two appliers, and each needs
  # this one to hold before its own question means anything.
  #
  # The scratch tier is what makes it askable. The procedure runs on a session of its own -
  # it holds a session-scoped lock across statements a concurrent index build forbids inside
  # a transaction - and a second session cannot see inside the sandboxed tier's one
  # never-committed transaction. Under the sandbox the guard blocks forever on the fixture's
  # own uncommitted DROP SCHEMA. Here "virgin" is literally true: the database is created
  # from template0 for this test and dropped after it.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Connection
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  # The second deploy's own context. Its timestamp is what tells a re-recorded file from an
  # untouched one: a version keeping the first run's time was not written again.
  @next_context %{@context | timestamp: ~U[2026-08-14 17:41:09.000000Z]}

  defp applied_migration_rows do
    statement = """
    SELECT "version", "applied_at" FROM "hologram_system"."migration" ORDER BY "version"
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [version, applied_at] -> {version, applied_at} end)
  end

  defp migration(version, ops) do
    %{version: version, path: "#{version}.exs", ops: ops}
  end

  defp table_columns(table) do
    statement = """
    SELECT a.attname
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hologram_data' AND c.relname = $1
      AND a.attnum > 0 AND NOT a.attisdropped
    ORDER BY a.attname
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [table])

    Enum.map(rows, fn [name] -> name end)
  end

  setup do
    chain = [
      migration("20260813091522", [
        %{op: :create_entity, entity: MyApp.Task, line: 3},
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :title,
          type: :string,
          opts: [],
          line: 4
        }
      ]),
      migration("20260813142237", [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :priority,
          type: :integer,
          opts: [optional: true],
          line: 3
        }
      ])
    ]

    model = Enum.reduce(chain, Model.empty(), &Model.fold(&2, &1.ops))

    [chain: chain, model: model]
  end

  describe "run/3" do
    test "claims the database and applies the pending suffix", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run(chain, model, @context) == :ok

        # The companion column rides the string attribute's declaration, so the layout the
        # chain leaves is the full derived one rather than the two attributes it names.
        assert table_columns("my_app_task") == [
                 "$revisions",
                 "created_at",
                 "id",
                 "priority",
                 "title",
                 "title_$sort",
                 "updated_at"
               ]

        assert Enum.map(applied_migration_rows(), fn {version, _applied_at} -> version end) ==
                 ["20260813091522", "20260813142237"]
      end)
    end

    test "leaves a database that already has the chain exactly as it was", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run(chain, model, @context) == :ok

        rows = applied_migration_rows()

        # A second deploy of the same release. Nothing is pending, so nothing applies - and
        # the timestamps prove it rather than the count: a file re-recorded under the second
        # context would carry its time.
        assert run(chain, model, @next_context) == :ok
        assert applied_migration_rows() == rows
      end)
    end
  end
end
