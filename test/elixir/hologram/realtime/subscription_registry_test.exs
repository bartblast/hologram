defmodule Hologram.Realtime.SubscriptionRegistryTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.SubscriptionRegistry

  alias Hologram.Realtime.SubscriptionRegistry

  setup do
    wait_for_process_cleanup(SubscriptionRegistry)
    start_supervised!(SubscriptionRegistry)

    :ok
  end

  describe "apply_deltas/4" do
    test "adds new bindings tagged with authorizing_user_id" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

      {add_keys, drop_keys} =
        apply_deltas(
          "test-instance-id",
          [{:room_a, "page"}, {:room_b, "comp_1"}],
          [],
          "test-user-id"
        )

      assert Enum.sort(add_keys) == [{:room_a, "page"}, {:room_b, "comp_1"}]
      assert drop_keys == []

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.bindings == %{
               {:room_a, "page"} => "test-user-id",
               {:room_b, "comp_1"} => "test-user-id"
             }
    end

    test "drops existing bindings" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

      apply_deltas(
        "test-instance-id",
        [{:room_a, "page"}, {:room_b, "comp_1"}],
        [],
        "test-user-id"
      )

      {add_keys, drop_keys} =
        apply_deltas("test-instance-id", [], [{:room_a, "page"}], "test-user-id")

      assert add_keys == []
      assert Enum.sort(drop_keys) == [{:room_a, "page"}]

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.bindings == %{{:room_b, "comp_1"} => "test-user-id"}
    end

    test "is a no-op when re-adding an already-present key (does not retag)" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

      apply_deltas("test-instance-id", [{:room_a, "page"}], [], "test-original-user-id")

      {add_keys, _drop_keys} =
        apply_deltas("test-instance-id", [{:room_a, "page"}], [], "test-different-user-id")

      assert add_keys == []

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.bindings == %{{:room_a, "page"} => "test-original-user-id"}
    end

    test "is a no-op when dropping a missing key" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

      apply_deltas("test-instance-id", [{:room_a, "page"}], [], "test-user-id")

      {_add_keys, drop_keys} =
        apply_deltas("test-instance-id", [], [{:room_b, "comp_1"}], "test-user-id")

      assert drop_keys == []

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.bindings == %{{:room_a, "page"} => "test-user-id"}
    end

    test "applies mixed adds and drops in a single call" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

      apply_deltas(
        "test-instance-id",
        [{:room_a, "page"}, {:room_b, "comp_1"}],
        [],
        "test-user-id"
      )

      {add_keys, drop_keys} =
        apply_deltas(
          "test-instance-id",
          [{:room_c, "comp_2"}],
          [{:room_a, "page"}],
          "test-user-id"
        )

      assert Enum.sort(add_keys) == [{:room_c, "comp_2"}]
      assert Enum.sort(drop_keys) == [{:room_a, "page"}]

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.bindings == %{
               {:room_b, "comp_1"} => "test-user-id",
               {:room_c, "comp_2"} => "test-user-id"
             }
    end

    test "persists authorizing_user_id per binding for both anonymous and authenticated values" do
      sse_pid_anon = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id-anon", sse_pid_anon)

      apply_deltas("test-instance-id-anon", [{:room_x, "page"}], [], nil)

      [{"test-instance-id-anon", anon_entry}] =
        :ets.lookup(ets_table_name(), "test-instance-id-anon")

      assert anon_entry.bindings == %{{:room_x, "page"} => nil}

      sse_pid_auth = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id-auth", sse_pid_auth)

      apply_deltas("test-instance-id-auth", [{:room_y, "page"}], [], "test-user-id")

      [{"test-instance-id-auth", auth_entry}] =
        :ets.lookup(ets_table_name(), "test-instance-id-auth")

      assert auth_entry.bindings == %{{:room_y, "page"} => "test-user-id"}
    end

    test "sends {:sub, channel} to sse_pid on add of the channel's first cid-binding" do
      :ok = register_connection("test-instance-id", self())

      apply_deltas("test-instance-id", [{:room_a, "page"}], [], "test-user-id")

      assert_receive {:sub, :room_a}
    end

    test "sends {:unsub, channel} to sse_pid on drop of the channel's last cid-binding" do
      :ok = register_connection("test-instance-id", self())

      apply_deltas("test-instance-id", [{:room_a, "page"}], [], "test-user-id")

      assert_receive {:sub, :room_a}

      apply_deltas("test-instance-id", [], [{:room_a, "page"}], "test-user-id")

      assert_receive {:unsub, :room_a}
    end

    test "sends no message when the channel still has other cid-bindings after the add" do
      :ok = register_connection("test-instance-id", self())

      apply_deltas("test-instance-id", [{:room_a, "page"}], [], "test-user-id")

      assert_receive {:sub, :room_a}

      apply_deltas("test-instance-id", [{:room_a, "comp_1"}], [], "test-user-id")

      refute_receive {:sub, :room_a}
    end

    test "sends no message when the channel still has other cid-bindings after the drop" do
      :ok = register_connection("test-instance-id", self())

      apply_deltas(
        "test-instance-id",
        [{:room_a, "page"}, {:room_a, "comp_1"}],
        [],
        "test-user-id"
      )

      assert_receive {:sub, :room_a}

      apply_deltas("test-instance-id", [], [{:room_a, "comp_1"}], "test-user-id")

      refute_receive {:unsub, :room_a}
    end

    test "preserves the surviving cid's binding when another cid for the same channel is dropped" do
      :ok = register_connection("test-instance-id", self())

      apply_deltas(
        "test-instance-id",
        [{:room_a, "page"}, {:room_a, "comp_1"}],
        [],
        "test-user-id"
      )

      apply_deltas("test-instance-id", [], [{:room_a, "comp_1"}], "test-user-id")

      assert bindings_of("test-instance-id") == %{{:room_a, "page"} => "test-user-id"}
    end

    test "sends no messages on idempotent re-add or idempotent drop-of-missing" do
      :ok = register_connection("test-instance-id", self())

      apply_deltas("test-instance-id", [{:room_a, "page"}], [], "test-user-id")

      assert_receive {:sub, :room_a}

      # Re-add an already-present key
      apply_deltas("test-instance-id", [{:room_a, "page"}], [], "test-user-id")

      refute_receive {:sub, _channel}
      refute_receive {:unsub, _channel}

      # Drop a missing key
      apply_deltas("test-instance-id", [], [{:room_b, "comp_1"}], "test-user-id")

      refute_receive {:sub, _channel}
      refute_receive {:unsub, _channel}
    end

    test "returns the input adds and drops for an unknown instance_id" do
      adds = [{:room_a, "page"}, {:room_b, "comp_1"}]
      drops = [{:room_c, "page"}]

      {add_keys, drop_keys} =
        apply_deltas("test-unknown-instance-id", adds, drops, "test-user-id")

      assert Enum.sort(add_keys) == Enum.sort(adds)
      assert Enum.sort(drop_keys) == Enum.sort(drops)
    end

    test "creates no entry for an unknown instance_id" do
      apply_deltas("test-unknown-instance-id", [{:room_a, "page"}], [], "test-user-id")

      assert :ets.lookup(ets_table_name(), "test-unknown-instance-id") == []
    end

    test "sends no zero-crossing messages for an unknown instance_id" do
      apply_deltas("test-unknown-instance-id", [{:room_a, "page"}], [], "test-user-id")

      refute_receive {:sub, _channel}
      refute_receive {:unsub, _channel}
    end
  end

  describe "attach_connection/5" do
    test "creates a fresh entry whose bindings field equals the supplied validated_bindings" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)

      attach_connection(
        "test-instance-id",
        "test-session-id",
        "test-user-id",
        sse_pid,
        [
          {{:room_a, "page"}, "test-user-id"},
          {{:room_b, "comp_1"}, "test-user-id"}
        ]
      )

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.bindings == %{
               {:room_a, "page"} => "test-user-id",
               {:room_b, "comp_1"} => "test-user-id"
             }

      assert entry.sse_pid == sse_pid
      assert entry.session_id == "test-session-id"
      assert entry.user_id == "test-user-id"
    end

    test "returns the deduped list of channels in the bindings set" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)

      validated_channels =
        attach_connection(
          "test-instance-id",
          "test-session-id",
          "test-user-id",
          sse_pid,
          [
            {{:room_a, "page"}, "test-user-id"},
            {{:room_a, "comp_1"}, "test-user-id"},
            {{:room_b, "page"}, "test-user-id"}
          ]
        )

      assert Enum.sort(validated_channels) == [:room_a, :room_b]
    end

    test "persists authorizing_user_id per binding for both anonymous and authenticated values" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)

      attach_connection(
        "test-instance-id",
        "test-session-id",
        "test-user-id",
        sse_pid,
        [
          {{:room_anon, "page"}, nil},
          {{:room_auth, "page"}, 7}
        ]
      )

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.bindings == %{
               {:room_anon, "page"} => nil,
               {:room_auth, "page"} => 7
             }
    end

    test "supersedes a prior live attachment: demonitors prior, sends :superseded, swaps the pid" do
      test_pid = self()

      # Forwards the first message it receives back to the test so we can
      # observe what the registry sent it.
      prior_pid =
        spawn(fn ->
          receive do
            msg -> send(test_pid, {:prior_received, msg})
          end
        end)

      new_pid = spawn(fn -> Process.sleep(:infinity) end)

      attach_connection("test-instance-id", nil, nil, prior_pid, [])
      attach_connection("test-instance-id", nil, nil, new_pid, [])

      assert_receive {:prior_received, {:close, :superseded}}

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.sse_pid == new_pid

      # Prior exits naturally after forwarding its one message; if demonitor
      # had failed, the :DOWN handler would delete the entry. Sync via an
      # unrelated GenServer call so any pending :DOWN has been processed.
      :ok = register_connection("sync-barrier", spawn(fn -> Process.sleep(:infinity) end))

      assert :ets.lookup(ets_table_name(), "test-instance-id") != []
    end

    test "preserves the prior bindings across a supersede" do
      prior_pid = spawn(fn -> Process.sleep(:infinity) end)
      new_pid = spawn(fn -> Process.sleep(:infinity) end)

      attach_connection(
        "test-instance-id",
        "old-session",
        "old-user",
        prior_pid,
        [
          {{:room_a, "page"}, "old-user"},
          {{:room_b, "comp_1"}, "old-user"}
        ]
      )

      # New client claims different bindings - registry should ignore them
      # and keep the prior canonical set.
      attach_connection(
        "test-instance-id",
        "new-session",
        "new-user",
        new_pid,
        [{{:room_c, "page"}, "new-user"}]
      )

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.bindings == %{
               {:room_a, "page"} => "old-user",
               {:room_b, "comp_1"} => "old-user"
             }

      assert entry.session_id == "new-session"
      assert entry.user_id == "new-user"
    end
  end

  describe "bindings_of/1" do
    test "returns the bindings map for a registered entry with seeded bindings" do
      :ok = register_connection("test-instance-id", self())

      apply_deltas(
        "test-instance-id",
        [{:room_a, "page"}, {:room_b, "comp_1"}],
        [],
        "test-user-id"
      )

      assert bindings_of("test-instance-id") == %{
               {:room_a, "page"} => "test-user-id",
               {:room_b, "comp_1"} => "test-user-id"
             }
    end

    test "returns the default empty map for a freshly registered entry" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

      assert bindings_of("test-instance-id") == %{}
    end

    test "returns nil for an unknown instance_id" do
      assert bindings_of("test-unknown-instance-id") == nil
    end
  end

  describe "drop_for_identity_change/2" do
    test "drops bindings whose authorizing_user_id is non-nil and not equal to new_user_id" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)
      apply_deltas("test-instance-id", [{:room_a, "page"}, {:room_b, "comp_1"}], [], 7)

      {dropped_keys, _zero_crossings} = drop_for_identity_change("test-instance-id", 8)

      assert Enum.sort(dropped_keys) == [{:room_a, "page"}, {:room_b, "comp_1"}]
      assert bindings_of("test-instance-id") == %{}
    end

    test "keeps anonymous-authorized bindings across the identity change" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)
      apply_deltas("test-instance-id", [{:room_a, "page"}], [], nil)
      apply_deltas("test-instance-id", [{:room_b, "comp_1"}], [], 7)

      {dropped_keys, _zero_crossings} = drop_for_identity_change("test-instance-id", 8)

      assert dropped_keys == [{:room_b, "comp_1"}]
      assert bindings_of("test-instance-id") == %{{:room_a, "page"} => nil}
    end

    test "keeps bindings already authorized by the new user_id" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)
      apply_deltas("test-instance-id", [{:room_a, "page"}], [], 7)
      apply_deltas("test-instance-id", [{:room_b, "comp_1"}], [], 8)

      {dropped_keys, _zero_crossings} = drop_for_identity_change("test-instance-id", 8)

      assert dropped_keys == [{:room_a, "page"}]
      assert bindings_of("test-instance-id") == %{{:room_b, "comp_1"} => 8}
    end

    test "returns a zero-crossing channel when its last cid-binding is dropped" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)
      apply_deltas("test-instance-id", [{:room_a, "page"}], [], 7)

      {_dropped_keys, zero_crossing_channels} = drop_for_identity_change("test-instance-id", 8)

      assert zero_crossing_channels == [:room_a]
    end

    test "does not return a channel that still has a surviving cid-binding" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)
      apply_deltas("test-instance-id", [{:room_a, "page"}], [], 7)
      apply_deltas("test-instance-id", [{:room_a, "comp_1"}], [], nil)

      {_dropped_keys, zero_crossing_channels} = drop_for_identity_change("test-instance-id", 8)

      assert zero_crossing_channels == []
    end

    test "returns {[], []} for an unknown instance_id" do
      assert drop_for_identity_change("test-unknown-instance-id", 8) == {[], []}
    end
  end

  describe "identity_of/1" do
    test "returns the defaulted {nil, nil} for a freshly registered entry" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

      assert identity_of("test-instance-id") == {nil, nil}
    end

    test "returns nil for an unknown instance_id" do
      assert identity_of("test-unknown-instance-id") == nil
    end
  end

  describe "register_connection/2" do
    test "inserts an entry whose sse_pid and sse_ref round-trip through the documented shape" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.sse_pid == sse_pid
      assert is_reference(entry.sse_ref)
    end

    test "defaults session_id and user_id to nil in the inserted entry" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.session_id == nil
      assert entry.user_id == nil
    end

    test "defaults bindings to an empty map in the inserted entry" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

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
    test "client-side diff is driven by client_claimed_sub_keys, not the registry's bindings" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

      # Seed the registry's bindings with one set
      transition("test-instance-id", [{:room_a, "page"}], [], "test-user-id")

      # new_sub_keys, client_claimed_sub_keys, and the registry's seeded bindings all differ
      {add_keys, drop_keys} =
        transition(
          "test-instance-id",
          [{:room_b, "page"}],
          [{:room_c, "page"}],
          "test-user-id"
        )

      assert Enum.sort(add_keys) == [{:room_b, "page"}]
      assert Enum.sort(drop_keys) == [{:room_c, "page"}]
    end

    test "replaces the registry's bindings field with the new set" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

      transition("test-instance-id", [{:room_a, "page"}, {:room_b, "comp_1"}], [], "test-user-id")

      [{"test-instance-id", entry}] = :ets.lookup(ets_table_name(), "test-instance-id")

      assert entry.bindings == %{
               {:room_a, "page"} => "test-user-id",
               {:room_b, "comp_1"} => "test-user-id"
             }
    end

    test "persists authorizing_user_id per binding for both anonymous and authenticated values" do
      sse_pid_anon = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id-anon", sse_pid_anon)
      transition("test-instance-id-anon", [{:room_x, "page"}], [], nil)

      [{"test-instance-id-anon", anon_entry}] =
        :ets.lookup(ets_table_name(), "test-instance-id-anon")

      assert anon_entry.bindings == %{{:room_x, "page"} => nil}

      sse_pid_auth = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id-auth", sse_pid_auth)
      transition("test-instance-id-auth", [{:room_y, "page"}], [], "test-user-id")

      [{"test-instance-id-auth", auth_entry}] =
        :ets.lookup(ets_table_name(), "test-instance-id-auth")

      assert auth_entry.bindings == %{{:room_y, "page"} => "test-user-id"}
    end

    test "returns empty add and drop lists when new_sub_keys fully overlap client_claimed_sub_keys" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

      bindings = [{:room_a, "page"}, {:room_b, "comp_1"}]
      {add_keys, drop_keys} = transition("test-instance-id", bindings, bindings, "test-user-id")

      assert add_keys == []
      assert drop_keys == []
    end

    test "returns correct add and drop lists for partial overlap" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

      {add_keys, drop_keys} =
        transition(
          "test-instance-id",
          [{:room_b, "page"}, {:room_c, "page"}],
          [{:room_a, "page"}, {:room_b, "page"}],
          "test-user-id"
        )

      assert Enum.sort(add_keys) == [{:room_c, "page"}]
      assert Enum.sort(drop_keys) == [{:room_a, "page"}]
    end

    test "sends {:sub, channel} to sse_pid on the first cid-binding for a channel" do
      :ok = register_connection("test-instance-id", self())

      transition("test-instance-id", [{:room_a, "page"}], [], "test-user-id")

      assert_receive {:sub, :room_a}
    end

    test "sends {:unsub, channel} to sse_pid when the last cid-binding for a channel is dropped" do
      :ok = register_connection("test-instance-id", self())

      transition("test-instance-id", [{:room_a, "page"}], [], "test-user-id")

      assert_receive {:sub, :room_a}

      transition("test-instance-id", [], [{:room_a, "page"}], "test-user-id")

      assert_receive {:unsub, :room_a}
    end

    test "sends no message when the channel still has other cid-bindings after the transition" do
      :ok = register_connection("test-instance-id", self())

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

    test "sends no messages when new_sub_keys fully overlap the registry's bindings" do
      :ok = register_connection("test-instance-id", self())

      bindings = [{:room_a, "page"}, {:room_b, "comp_1"}]
      transition("test-instance-id", bindings, [], "test-user-id")

      assert_receive {:sub, :room_a}
      assert_receive {:sub, :room_b}

      transition("test-instance-id", bindings, bindings, "test-user-id")

      refute_receive {:sub, _channel}
      refute_receive {:unsub, _channel}
    end

    test "returns the client-side diff for an unknown instance_id" do
      {add_keys, drop_keys} =
        transition(
          "test-unknown-instance-id",
          [{:room_a, "page"}, {:room_b, "page"}],
          [{:room_b, "page"}, {:room_c, "page"}],
          "test-user-id"
        )

      assert Enum.sort(add_keys) == [{:room_a, "page"}]
      assert Enum.sort(drop_keys) == [{:room_c, "page"}]
    end

    test "creates no entry for an unknown instance_id" do
      transition("test-unknown-instance-id", [{:room_a, "page"}], [], "test-user-id")

      assert :ets.lookup(ets_table_name(), "test-unknown-instance-id") == []
    end

    test "sends no zero-crossing messages for an unknown instance_id" do
      transition("test-unknown-instance-id", [{:room_a, "page"}], [], "test-user-id")

      refute_receive {:sub, _channel}
      refute_receive {:unsub, _channel}
    end
  end

  describe "update_identity/3" do
    test "updates session_id and user_id on an existing entry" do
      sse_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id", sse_pid)

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
      :ok = register_connection("test-instance-id", sse_pid)

      test_ref = Process.monitor(sse_pid)
      Process.exit(sse_pid, :kill)
      assert_receive {:DOWN, ^test_ref, :process, _object, _reason}

      # Sync with the registry's mailbox so its DOWN is processed before we check ETS
      :sys.get_state(SubscriptionRegistry)

      assert :ets.lookup(ets_table_name(), "test-instance-id") == []
    end

    test "leaves entries for other instances untouched when one pid dies" do
      sse_pid_a = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id-a", sse_pid_a)

      sse_pid_b = spawn(fn -> Process.sleep(:infinity) end)
      :ok = register_connection("test-instance-id-b", sse_pid_b)

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
      :ok = register_connection("test-instance-id", sse_pid)

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
