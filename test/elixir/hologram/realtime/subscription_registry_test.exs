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
  end
end
