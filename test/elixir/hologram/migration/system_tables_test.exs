defmodule Hologram.Migration.SystemTablesTest do
  # A deploy meeting a database whose hologram_system tables are at another layout than the one
  # its Hologram runs. Through real boots, since a boot reads the marker before it takes the
  # migration lock and treats whatever it can't read there as something to do (see
  # Hologram.Migrator.up_to_date?/3) - only a committed marker shows what the boot makes of it.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Connection
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  # An upgrade step standing in for a later release's, creating a table that fails if it runs
  # again.
  @probe_step {2, [~s{CREATE TABLE "hologram_system"."upgrade_probe" ("id" integer)}]}

  # The test config logs warnings and up - the upgrade lines are info.
  defp capture_info_log(fun) do
    level = Logger.level()
    Logger.configure(level: :info)

    try do
      ExUnit.CaptureLog.capture_log([level: :info], fun)
    after
      Logger.configure(level: level)
    end
  end

  defp migration(version, ops) do
    %{version: version, path: "app/migrations/#{version}.ex", ops: ops}
  end

  defp probe_exists? do
    statement = ~s{SELECT to_regclass('"hologram_system"."upgrade_probe"') IS NOT NULL}
    {:ok, %{rows: [[exists?]]}} = Connection.query(statement)

    exists?
  end

  defp set_system_schema_version(version) do
    statement = ~s(UPDATE "hologram_system"."database" SET "system_schema_version" = $1)
    {:ok, _result} = Connection.query(statement, [version])
  end

  # A boot on a session of its own, held at the gate until every one of them is connected - so the
  # race is between two nodes that really do arrive together.
  defp start_booter(chain, model, context, scratch_opts, test_pid) do
    Task.async(fn ->
      {:ok, session} = Postgrex.start_link(scratch_opts)

      send(test_pid, {:ready, self()})

      receive do
        :go -> :ok
      end

      route(session, fn -> run(chain, model, context) end)
    end)
  end

  # A database an earlier boot claimed and brought up to date, at layout 1.
  setup %{scratch: scratch} do
    create = migration("20260813091522", [%{op: :create_entity, entity: MyApp.Task, line: 3}])
    model = Model.fold(Model.empty(), create.ops)

    route(scratch, fn -> :ok = run([create], model, @context) end)

    [chain: [create], model: model]
  end

  describe "run/3" do
    test "upgrades the system tables of a database at an older layout", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        context = Map.put(@context, :system_upgrades, [@probe_step])

        log = capture_info_log(fn -> assert run(chain, model, context) == :ok end)

        assert probe_exists?()
        assert SchemaReconciler.read_marker().system_schema_version == 2
        assert log =~ "Hologram: upgraded the system tables to layout version 2"

        # The next boot finds the layout current, so the step's CREATE TABLE doesn't run again.
        assert run(chain, model, context) == :ok
      end)
    end

    test "upgrades once across two boots racing for it", %{
      chain: chain,
      model: model,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      test_pid = self()
      context = Map.put(@context, :system_upgrades, [@probe_step])

      booters =
        Enum.map(1..2, fn _index ->
          start_booter(chain, model, context, scratch_opts, test_pid)
        end)

      Enum.each(booters, fn _booter -> assert_receive {:ready, _pid}, 5_000 end)
      Enum.each(booters, fn booter -> send(booter.pid, :go) end)

      # The one that takes the lock second finds the step done inside it, rather than failing on a
      # table that already exists. Both reach the lock in practice: a boot that looked only after
      # the other committed would skip it, which passes too, so the race is only as sharp as the
      # gate makes it.
      assert Task.await_many(booters, 30_000) == [:ok, :ok]

      route(scratch, fn ->
        assert probe_exists?()
        assert SchemaReconciler.read_marker().system_schema_version == 2
      end)
    end

    test "rolls back every upgrade step with one the database refuses, naming its version", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        # Step 2 runs before step 3 is refused, so its table being gone shows the whole upgrade
        # is one transaction, and no line naming either shows the log waits for the commit.
        context = Map.put(@context, :system_upgrades, [@probe_step, {3, ["SELECT 1 / 0"]}])

        log =
          capture_info_log(fn ->
            assert_error RuntimeError,
                         "upgrading the system tables to layout version 3 failed - " <>
                           "ERROR 22012 (division_by_zero) division by zero",
                         fn -> run(chain, model, context) end
          end)

        refute probe_exists?()
        assert SchemaReconciler.read_marker().system_schema_version == 1
        refute log =~ "upgraded the system tables"
      end)
    end

    test "refuses to boot a database a newer Hologram upgraded", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        set_system_schema_version(3)

        expected_msg =
          "the configured database's system tables are at layout version 3, from a newer " <>
            "Hologram - this Hologram knows layout versions up to 2 - upgrade Hologram or " <>
            "point the config at another database"

        assert_error RuntimeError, expected_msg, fn ->
          run(chain, model, Map.put(@context, :system_upgrades, [{2, []}]))
        end
      end)
    end
  end
end
