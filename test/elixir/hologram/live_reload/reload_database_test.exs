defmodule Hologram.LiveReload.ReloadDatabaseTest do
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.LiveReload

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Introspection
  alias Hologram.DB.Schema
  alias Hologram.Reflection

  describe "reload_database/2" do
    test "reconciles the schema with the given data model" do
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_system" CASCADE))
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))

      assert reload_database(Reflection.list_entities(), Reflection.list_roles()) == :ok

      assert Introspection.schema() == Schema.from_mapping(DB.mapping())
    end

    test "raises a failure as it is" do
      expected_msg =
        normalize_newlines("""
        colliding table names - rename modules so that every entity type derives a unique table name:
          * table name "blog_post" is derived from Hologram.Blog.Post, Hologram.BlogPost\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        reload_database([Hologram.Blog.Post, Hologram.BlogPost], [])
      end
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
        Connection.with_connection(dead_connection, fn ->
          reload_database(Reflection.list_entities(), Reflection.list_roles())
        end)
      end
    end
  end
end
