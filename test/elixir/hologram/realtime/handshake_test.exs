defmodule Hologram.Realtime.HandshakeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.Handshake

  alias Hologram.Realtime.Handshake

  defp wait_for_waiter(handshake_id) do
    wait_until(fn -> match?(%{^handshake_id => _waiters}, :sys.get_state(Handshake).waiters) end)
  end

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(Handshake)
    start_supervised!(Handshake)

    :ok
  end

  describe "insert/4" do
    test "stashes the handshake entry in ETS with the identity tuple flattened" do
      future = System.system_time(:millisecond) + 60_000

      insert(
        "test-handshake-id",
        [{{:room_a, "page"}, "test-user-id"}],
        {"test-instance-id", "test-session-id", "test-user-id"},
        future
      )

      assert :ets.lookup(ets_table_name(), "test-handshake-id") == [
               {
                 "test-handshake-id",
                 [{{:room_a, "page"}, "test-user-id"}],
                 "test-instance-id",
                 "test-session-id",
                 "test-user-id",
                 future
               }
             ]
    end

    test "broadcasts the insert on the gossip topic with the flattened wire shape" do
      :ok = Phoenix.PubSub.subscribe(Hologram.PubSub, gossip_topic())

      future = System.system_time(:millisecond) + 60_000

      insert(
        "test-handshake-id",
        [{{:room_a, "page"}, "test-user-id"}],
        {"test-instance-id", "test-session-id", "test-user-id"},
        future
      )

      assert_receive {
        :insert,
        "test-handshake-id",
        [{{:room_a, "page"}, "test-user-id"}],
        "test-instance-id",
        "test-session-id",
        "test-user-id",
        ^future
      }
    end
  end

  describe "redeem/2" do
    test "returns the stashed entry's bindings and identity immediately on ETS hit" do
      future = System.system_time(:millisecond) + 60_000

      insert(
        "stashed-handshake-id",
        [{{:room_a, "page"}, "test-user-id"}],
        {"test-instance-id", "test-session-id", "test-user-id"},
        future
      )

      assert redeem("stashed-handshake-id", 1_000) ==
               {:ok, [{{:room_a, "page"}, "test-user-id"}],
                {"test-instance-id", "test-session-id", "test-user-id"}}
    end

    test "returns :error and deletes the entry when it is already expired" do
      past = System.system_time(:millisecond) - 1

      insert(
        "expired-handshake-id",
        [{{:room_a, "page"}, "test-user-id"}],
        {"test-instance-id", "test-session-id", "test-user-id"},
        past
      )

      assert redeem("expired-handshake-id", 50) == :error

      assert :ets.lookup(ets_table_name(), "expired-handshake-id") == []
    end

    test "returns :error after the per-call timeout when the entry never arrives" do
      assert redeem("missing-handshake-id", 50) == :error
    end

    test "removes the timed-out waiter from state" do
      assert redeem("missing-handshake-id", 50) == :error

      assert :sys.get_state(Handshake) == %{waiters: %{}}
    end

    test "resolves a pending waiter when a local insert lands" do
      task = Task.async(fn -> redeem("late-handshake-id", 1_000) end)

      wait_for_waiter("late-handshake-id")

      insert(
        "late-handshake-id",
        [{{:room_a, "page"}, "test-user-id"}],
        {"test-instance-id", "test-session-id", "test-user-id"},
        System.system_time(:millisecond) + 60_000
      )

      assert Task.await(task) ==
               {:ok, [{{:room_a, "page"}, "test-user-id"}],
                {"test-instance-id", "test-session-id", "test-user-id"}}
    end

    # Without this the async sync would regress the guarantee the blocking one gave by
    # construction: a redeem parked before a peer's reply lands must be answered by it.
    test "resolves a pending waiter when a peer's sync reply carries the handshake" do
      task = Task.async(fn -> redeem("late-handshake-id", 1_000) end)

      wait_for_waiter("late-handshake-id")

      future = System.system_time(:millisecond) + 60_000

      send(
        Process.whereis(Handshake),
        {:sync_reply,
         [
           {"late-handshake-id", [{{:room_a, "page"}, "test-user-id"}], "peer-instance-id",
            "peer-session-id", "peer-user-id", future}
         ]}
      )

      assert Task.await(task) ==
               {:ok, [{{:room_a, "page"}, "test-user-id"}],
                {"peer-instance-id", "peer-session-id", "peer-user-id"}}
    end

    test "resolves a pending waiter when a peer gossip insert arrives" do
      task = Task.async(fn -> redeem("late-handshake-id", 1_000) end)

      wait_for_waiter("late-handshake-id")

      future = System.system_time(:millisecond) + 60_000

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        gossip_topic(),
        {:insert, "late-handshake-id", [{{:room_a, "page"}, "test-user-id"}], "peer-instance-id",
         "peer-session-id", "peer-user-id", future}
      )

      assert Task.await(task) ==
               {:ok, [{{:room_a, "page"}, "test-user-id"}],
                {"peer-instance-id", "peer-session-id", "peer-user-id"}}
    end
  end

  describe "start_link/1" do
    # The reason the sync request does not wait: a node that is accepting requests has
    # to answer them. Against a blocking boot sync this call exits on its own timeout.
    test "answers a redeem straight away, without waiting on peers" do
      :ok = stop_supervised(Handshake)

      start_supervised!(Handshake)

      assert redeem("never-stashed-id", 100) == :error
    end

    test "starts with an empty stash when no peer replies" do
      :ok = stop_supervised(Handshake)

      start_supervised!(Handshake)

      # A synchronous call returns only once init/1 has run.
      :sys.get_state(Handshake)

      assert :ets.tab2list(ets_table_name()) == []
    end

    # Asking is per connected node, so there is nobody to ask here. That a peer receives
    # the request and answers it is cluster-suite territory - what this pins is that
    # starting up asks without waiting, and stays open to gossip afterwards.
    test "still merges a steady-state {:insert, ...} a peer publishes after starting" do
      :ok = stop_supervised(Handshake)

      start_supervised!(Handshake)

      future = System.system_time(:millisecond) + 60_000

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        gossip_topic(),
        {:insert, "post-start-handshake-id", [], "peer-instance-id", "peer-session-id",
         "peer-user-id", future}
      )

      wait_until(fn ->
        match?(
          [
            {"post-start-handshake-id", [], "peer-instance-id", "peer-session-id", "peer-user-id",
             ^future}
          ],
          :ets.lookup(ets_table_name(), "post-start-handshake-id")
        )
      end)

      assert [
               {"post-start-handshake-id", [], "peer-instance-id", "peer-session-id",
                "peer-user-id", ^future}
             ] = :ets.lookup(ets_table_name(), "post-start-handshake-id")
    end
  end

  describe "sweep_expired/0" do
    test "deletes entries whose expires_at is in the past" do
      past = System.system_time(:millisecond) - 1_000

      insert(
        "expired-handshake-id",
        [],
        {"test-instance-id", "test-session-id", "test-user-id"},
        past
      )

      :ok = sweep_expired()

      assert :ets.lookup(ets_table_name(), "expired-handshake-id") == []
    end

    test "preserves entries whose expires_at is in the future" do
      future = System.system_time(:millisecond) + 60_000

      insert(
        "live-handshake-id",
        [],
        {"test-instance-id", "test-session-id", "test-user-id"},
        future
      )

      :ok = sweep_expired()

      assert [
               {"live-handshake-id", _validated_bindings, _instance_id, _session_id, _user_id,
                ^future}
             ] = :ets.lookup(ets_table_name(), "live-handshake-id")
    end
  end

  describe "handle {:insert, ...}" do
    test "merges a peer-broadcasted entry into ETS" do
      future = System.system_time(:millisecond) + 60_000

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        gossip_topic(),
        {:insert, "peer-handshake-id", [], "peer-instance-id", "peer-session-id", "peer-user-id",
         future}
      )

      # Sync with the GenServer to ensure the broadcasted :insert has been
      # processed before we read the ETS. sweep_expired/0 is a synchronous
      # GenServer.call that runs after any pending :insert in the mailbox;
      # the future expires_at keeps the entry alive across the sweep.
      :ok = sweep_expired()

      assert [
               {"peer-handshake-id", [], "peer-instance-id", "peer-session-id", "peer-user-id",
                ^future}
             ] = :ets.lookup(ets_table_name(), "peer-handshake-id")
    end
  end

  describe "handle {:sync_reply, ...}" do
    test "merges a peer's handshakes into ETS" do
      future = System.system_time(:millisecond) + 60_000

      send(
        Process.whereis(Handshake),
        {:sync_reply,
         [
           {"synced-handshake-id", [], "peer-instance-id", "peer-session-id", "peer-user-id",
            future}
         ]}
      )

      :ok = sweep_expired()

      assert [
               {"synced-handshake-id", [], "peer-instance-id", "peer-session-id", "peer-user-id",
                ^future}
             ] = :ets.lookup(ets_table_name(), "synced-handshake-id")
    end

    # A peer answers out of its own table, which still holds whatever its last sweep has
    # not reached, so what arrives can already be past its expiry.
    test "ignores a handshake that has already expired" do
      past = System.system_time(:millisecond) - 1

      send(
        Process.whereis(Handshake),
        {:sync_reply,
         [
           {"expired-handshake-id", [], "peer-instance-id", "peer-session-id", "peer-user-id",
            past}
         ]}
      )

      :ok = sweep_expired()

      assert :ets.lookup(ets_table_name(), "expired-handshake-id") == []
    end

    # Waking a waiter is how a redeem gets its answer, so an expired handshake must not
    # wake one - that reply would be an :ok redeem/2 itself would have refused.
    test "leaves a waiter parked when the handshake it waits for has expired" do
      task = Task.async(fn -> redeem("expired-handshake-id", 200) end)

      wait_for_waiter("expired-handshake-id")

      past = System.system_time(:millisecond) - 1

      send(
        Process.whereis(Handshake),
        {:sync_reply,
         [
           {"expired-handshake-id", [], "peer-instance-id", "peer-session-id", "peer-user-id",
            past}
         ]}
      )

      assert Task.await(task) == :error
    end
  end

  describe "handle {:nodeup, ...}" do
    # A boot-time request only reaches peers this node can already see. Watching joins is
    # what lets a store that booted into a still-forming cluster catch up afterwards.
    test "asks the joining node for what it holds" do
      Phoenix.PubSub.subscribe(Hologram.PubSub, gossip_topic())

      handshake_pid = Process.whereis(Handshake)

      send(handshake_pid, {:nodeup, node()})

      assert_receive {:sync_request, ^handshake_pid}
    end
  end

  describe "handle {:sync_request, ...}" do
    test "replies with the current ETS dump via direct send" do
      future = System.system_time(:millisecond) + 60_000

      insert(
        "stashed-handshake-id",
        [{{:room_a, "page"}, "test-user-id"}],
        {"test-instance-id", "test-session-id", "test-user-id"},
        future
      )

      send(Process.whereis(Handshake), {:sync_request, self()})

      assert_receive {:sync_reply, entries}

      assert entries == [
               {
                 "stashed-handshake-id",
                 [{{:room_a, "page"}, "test-user-id"}],
                 "test-instance-id",
                 "test-session-id",
                 "test-user-id",
                 future
               }
             ]
    end
  end
end
