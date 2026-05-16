defmodule Hologram.Realtime.SubscriptionRegistryTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.SubscriptionRegistry

  alias Hologram.Realtime.SubscriptionRegistry

  setup do
    wait_for_process_cleanup(SubscriptionRegistry)
    start_supervised!(SubscriptionRegistry)

    :ok
  end

  test "starts under a supervisor and registers itself by module name" do
    assert process_name_registered?(SubscriptionRegistry)
  end

  test "creates the backing ETS table with the documented name and options" do
    table_name = ets_table_name()

    assert table_name == :hologram_subscriptions
    assert ets_table_name_registered?(table_name)

    info = :ets.info(table_name)

    assert info[:type] == :set
    assert info[:protection] == :public
    assert info[:named_table] == true
    assert info[:read_concurrency] == true
  end

  describe "register/2" do
    test "inserts an entry whose sse_pid and sse_ref round-trip through the documented shape" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id", sse_pid)

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.sse_pid == sse_pid
      assert is_reference(entry.sse_ref)
    end

    test "defaults session_id and user_id to nil in the inserted entry" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id", sse_pid)

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.session_id == nil
      assert entry.user_id == nil
    end
  end

  describe "{:DOWN, ...} cleanup" do
    test "deletes the entry when the monitored SSE pid dies" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id", sse_pid)

      test_ref = Process.monitor(sse_pid)
      Process.exit(sse_pid, :kill)
      assert_receive {:DOWN, ^test_ref, :process, _object, _reason}

      # Sync with the registry's mailbox so its DOWN is processed before we check ETS
      :sys.get_state(SubscriptionRegistry)

      assert :ets.lookup(ets_table_name(), "test-instance-id") == []
    end

    test "leaves entries for other instances untouched when one pid dies" do
      sse_pid_a = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id-a", sse_pid_a)

      sse_pid_b = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id-b", sse_pid_b)

      test_ref = Process.monitor(sse_pid_a)
      Process.exit(sse_pid_a, :kill)
      assert_receive {:DOWN, ^test_ref, :process, _object, _reason}

      # Sync with the registry's mailbox so its DOWN is processed before we check ETS
      :sys.get_state(SubscriptionRegistry)

      assert :ets.lookup(ets_table_name(), "test-instance-id-a") == []

      assert [{"test-instance-id-b", _entry}] =
               :ets.lookup(ets_table_name(), "test-instance-id-b")
    end

    test "ignores DOWN messages from non-monitored refs and leaves existing entries untouched" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id", sse_pid)

      send(
        Process.whereis(SubscriptionRegistry),
        {:DOWN, make_ref(), :process, self(), :normal}
      )

      # Sync with the registry's mailbox so its DOWN is processed before we check ETS
      :sys.get_state(SubscriptionRegistry)

      assert [{"test-instance-id", _entry}] = :ets.lookup(ets_table_name(), "test-instance-id")
    end
  end
end
