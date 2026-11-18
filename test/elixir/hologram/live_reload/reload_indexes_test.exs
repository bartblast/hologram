defmodule Hologram.LiveReload.ReloadIndexesTest do
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.LiveReload

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.IndexPlan
  alias Hologram.DB.Introspection
  alias Hologram.DB.Schema

  @plan_key {Hologram.DB, :plan}

  # A plan no reconciliation converges to, so that the reload reconciles.
  setup do
    original_plan = :persistent_term.get(@plan_key, nil)
    :persistent_term.put(@plan_key, :none)

    on_exit(fn ->
      if original_plan,
        do: :persistent_term.put(@plan_key, original_plan),
        else: :persistent_term.erase(@plan_key)
    end)
  end

  describe "reload_indexes/0" do
    test "reconciles the schema with the index plan" do
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_system" CASCADE))
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))

      assert reload_indexes() == :ok

      assert Introspection.schema() ==
               Schema.from_mapping(DB.mapping(), IndexPlan.plan(DB.mapping()))
    end

    test "raises an exit as a compile error" do
      dead_connection = spawn(fn -> :ok end)
      monitor_ref = Process.monitor(dead_connection)
      assert_receive {:DOWN, ^monitor_ref, :process, _pid, _reason}

      expected_msg =
        normalize_newlines("""
        database reload failed: exited in: DBConnection.Holder.checkout(#{inspect(dead_connection)}, [timeout: :infinity])
            ** (EXIT) no process: the process is not alive or there's no process currently associated with the given name, possibly because its application isn't started\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        Connection.with_connection(dead_connection, fn -> reload_indexes() end)
      end
    end
  end
end
