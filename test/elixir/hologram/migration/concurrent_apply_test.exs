defmodule Hologram.Migration.ConcurrentApplyTest do
  # Two nodes of one deploy reaching a database at the same moment. Everything they race
  # for is here: an unclaimed database both would claim, and a chain both would apply.
  #
  # The advisory lock the appliers share is what makes the answer a single one - the first
  # node through does the work, and the others re-read the bookkeeping INSIDE their own
  # transaction and find it already done. That re-read is the part worth testing: a node
  # that decided what was pending before taking the lock would apply a file twice.
  #
  # The deterministic twin of the cluster suite's concurrent-boot test, which runs the same
  # race between real peer nodes. That one stays as it is - it proves the race survives a
  # real boot, this one proves the outcome holds however the two interleave.
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

  defp applied_migration_rows do
    statement = """
    SELECT "version", "applied_at" FROM "hologram_system"."migration" ORDER BY "version"
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [version, applied_at] -> {version, applied_at} end)
  end

  defp marker_count do
    {:ok, %{rows: [[count]]}} =
      Connection.query(~s{SELECT COUNT(*) FROM "hologram_system"."database"})

    count
  end

  defp migration(version, ops) do
    %{version: version, path: "#{version}.exs", ops: ops}
  end

  # An applier on a session of its own, held at the gate until every one of them is
  # connected - so the race is between two nodes that really do arrive together, rather
  # than between one that has finished and one that has not started.
  defp start_applier(chain, model, scratch_opts, test_pid) do
    Task.async(fn ->
      {:ok, session} = Postgrex.start_link(scratch_opts)

      send(test_pid, {:ready, self()})

      receive do
        :go -> :ok
      end

      route(session, fn -> run(chain, model, @context) end)
    end)
  end

  defp task_columns do
    statement = """
    SELECT a.attname
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hologram_data' AND c.relname = 'my_app_task'
      AND a.attnum > 0 AND NOT a.attisdropped
    ORDER BY a.attname
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [name] -> name end)
  end

  setup do
    create =
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
      ])

    extend =
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

    first_model = Model.fold(Model.empty(), create.ops)
    full_model = Model.fold(first_model, extend.ops)

    [chain: [create, extend], full_model: full_model]
  end

  describe "run/3" do
    test "applies the chain exactly once across two appliers racing for it", %{
      chain: chain,
      full_model: full_model,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      test_pid = self()

      appliers =
        Enum.map(1..2, fn _index ->
          start_applier(chain, full_model, scratch_opts, test_pid)
        end)

      Enum.each(appliers, fn _applier -> assert_receive {:ready, _pid}, 5_000 end)
      Enum.each(appliers, fn applier -> send(applier.pid, :go) end)

      # Neither refuses: the one that loses the race finds the work done and passes
      # through, rather than failing on a table that already exists.
      assert Task.await_many(appliers, 30_000) == [:ok, :ok]

      route(scratch, fn ->
        # One row per version, so no file was applied twice - and one marker, so the
        # virgin database was claimed once even though both nodes found it unclaimed.
        assert applied_migration_rows() == [
                 {"20260813091522", @context.timestamp},
                 {"20260813142237", @context.timestamp}
               ]

        assert marker_count() == 1

        assert task_columns() == [
                 "$revisions",
                 "created_at",
                 "id",
                 "priority",
                 "title",
                 "title_$sort",
                 "updated_at"
               ]
      end)
    end
  end
end
