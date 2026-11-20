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
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  defp migration(version, ops) do
    %{version: version, path: "app/migrations/#{version}.ex", ops: ops}
  end

  defp set_system_schema_version(version) do
    statement = ~s(UPDATE "hologram_system"."database" SET "system_schema_version" = $1)
    {:ok, _result} = Connection.query(statement, [version])
  end

  # A database an earlier boot claimed and brought up to date, at layout 1.
  setup %{scratch: scratch} do
    create = migration("20260813091522", [%{op: :create_entity, entity: MyApp.Task, line: 3}])
    model = Model.fold(Model.empty(), create.ops)

    route(scratch, fn -> :ok = run([create], model, @context) end)

    [chain: [create], model: model]
  end

  describe "run/3" do
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
