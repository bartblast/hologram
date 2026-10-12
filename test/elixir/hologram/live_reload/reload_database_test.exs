defmodule Hologram.LiveReload.ReloadDatabaseTest do
  use Hologram.Test.DatabaseCase, async: false

  import ExUnit.CaptureLog
  import Hologram.LiveReload

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Introspection
  alias Hologram.DB.Schema
  alias Hologram.LiveReload.Diagnostic
  alias Hologram.Reflection

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram_live_reload")

    :ok
  end

  describe "reload_database/2" do
    test "reconciles the schema with the given data model" do
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_system" CASCADE))
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))

      assert reload_database(Reflection.list_entities(), Reflection.list_roles()) == :ok

      assert Introspection.schema() == Schema.from_mapping(DB.mapping())
      refute_received {:compilation_error, _lines}
    end

    test "broadcasts a failure as a compilation error and raises it" do
      expected_msg =
        normalize_newlines("""
        colliding table names - rename modules so that every entity type derives a unique table name:
          * table name "blog_post" is derived from Hologram.Blog.Post, Hologram.BlogPost\
        """)

      log =
        capture_log(fn ->
          assert_error Hologram.CompileError, expected_msg, fn ->
            reload_database([Hologram.Blog.Post, Hologram.BlogPost], [])
          end
        end)

      assert log =~ "Hologram: data layer reload failed: #{expected_msg}"

      assert_receive {:compilation_error, lines}
      assert lines == Diagnostic.to_lines(expected_msg)
    end
  end
end
