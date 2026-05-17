defmodule Hologram.Realtime.SubscriptionRegistryTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.SubscriptionRegistry

  alias Hologram.Realtime.SubscriptionRegistry

  setup do
    wait_for_process_cleanup(SubscriptionRegistry)
    start_supervised!(SubscriptionRegistry)

    :ok
  end

  describe "identity_of/1" do
    test "returns the defaulted {nil, nil} for a freshly registered entry" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id", sse_pid)

      assert identity_of("test-instance-id") == {nil, nil}
    end

    test "returns nil for an unknown instance_id" do
      assert identity_of("test-unknown-instance-id") == nil
    end
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

    test "defaults bindings to an empty map in the inserted entry" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id", sse_pid)

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.bindings == %{}
    end
  end

  describe "start_link/1" do
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
  end

  describe "transition/4" do
    test "client-side diff is driven by client_supplied_keys, not the registry's bindings" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id", sse_pid)

      # Seed the registry's bindings with one set
      transition("test-instance-id", [{:room_a, "page"}], [], "test-user-id")

      # new_bindings, client_supplied_keys, and the registry's seeded bindings all differ
      {add_keys, drop_keys} =
        transition(
          "test-instance-id",
          [{:room_b, "page"}],
          [{:room_c, "page"}],
          "test-user-id"
        )

      assert MapSet.new(add_keys) == MapSet.new([{:room_b, "page"}])
      assert MapSet.new(drop_keys) == MapSet.new([{:room_c, "page"}])
    end

    test "replaces the registry's bindings field with the new set" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id", sse_pid)

      transition("test-instance-id", [{:room_a, "page"}, {:room_b, "comp_1"}], [], "test-user-id")

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.bindings == %{
               {:room_a, "page"} => "test-user-id",
               {:room_b, "comp_1"} => "test-user-id"
             }
    end

    test "persists authorizing_user_id per binding for both anonymous and authenticated values" do
      sse_pid_anon = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id-anon", sse_pid_anon)
      transition("test-instance-id-anon", [{:room_x, "page"}], [], nil)

      [{"test-instance-id-anon", anon_entry}] =
        :ets.lookup(ets_table_name(), "test-instance-id-anon")

      assert anon_entry.bindings == %{{:room_x, "page"} => nil}

      sse_pid_auth = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id-auth", sse_pid_auth)
      transition("test-instance-id-auth", [{:room_y, "page"}], [], "test-user-id")

      [{"test-instance-id-auth", auth_entry}] =
        :ets.lookup(ets_table_name(), "test-instance-id-auth")

      assert auth_entry.bindings == %{{:room_y, "page"} => "test-user-id"}
    end

    test "returns empty add and drop lists when new_bindings fully overlap client_supplied_keys" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id", sse_pid)

      bindings = [{:room_a, "page"}, {:room_b, "comp_1"}]
      {add_keys, drop_keys} = transition("test-instance-id", bindings, bindings, "test-user-id")

      assert add_keys == []
      assert drop_keys == []
    end

    test "returns correct add and drop lists for partial overlap" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id", sse_pid)

      {add_keys, drop_keys} =
        transition(
          "test-instance-id",
          [{:room_b, "page"}, {:room_c, "page"}],
          [{:room_a, "page"}, {:room_b, "page"}],
          "test-user-id"
        )

      assert MapSet.new(add_keys) == MapSet.new([{:room_c, "page"}])
      assert MapSet.new(drop_keys) == MapSet.new([{:room_a, "page"}])
    end

    test "sends {:sub, channel} to sse_pid on the first cid-binding for a channel" do
      :ok = register("test-instance-id", self())

      transition("test-instance-id", [{:room_a, "page"}], [], "test-user-id")

      assert_receive {:sub, :room_a}
    end

    test "sends {:unsub, channel} to sse_pid when the last cid-binding for a channel is dropped" do
      :ok = register("test-instance-id", self())

      transition("test-instance-id", [{:room_a, "page"}], [], "test-user-id")

      assert_receive {:sub, :room_a}

      transition("test-instance-id", [], [{:room_a, "page"}], "test-user-id")

      assert_receive {:unsub, :room_a}
    end

    test "sends no message when the channel still has other cid-bindings after the transition" do
      :ok = register("test-instance-id", self())

      transition(
        "test-instance-id",
        [{:room_a, "page"}, {:room_a, "comp_1"}],
        [],
        "test-user-id"
      )

      assert_receive {:sub, :room_a}

      # Drop one cid and add another for the same channel - channel always has >=1 binding
      transition(
        "test-instance-id",
        [{:room_a, "page"}, {:room_a, "comp_2"}],
        [{:room_a, "comp_1"}],
        "test-user-id"
      )

      refute_receive {:sub, :room_a}
      refute_receive {:unsub, :room_a}
    end

    test "sends no messages when new_bindings fully overlap the registry's bindings" do
      :ok = register("test-instance-id", self())

      bindings = [{:room_a, "page"}, {:room_b, "comp_1"}]
      transition("test-instance-id", bindings, [], "test-user-id")

      assert_receive {:sub, :room_a}
      assert_receive {:sub, :room_b}

      transition("test-instance-id", bindings, bindings, "test-user-id")

      refute_receive {:sub, _channel}
      refute_receive {:unsub, _channel}
    end
  end

  describe "update_identity/3" do
    test "updates session_id and user_id on an existing entry" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register("test-instance-id", sse_pid)

      :ok = update_identity("test-instance-id", "test-session-id", "test-user-id")

      assert identity_of("test-instance-id") == {"test-session-id", "test-user-id"}
    end

    test "is a no-op for an unknown instance_id" do
      :ok = update_identity("test-unknown-instance-id", "test-session-id", "test-user-id")

      assert identity_of("test-unknown-instance-id") == nil
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
