defmodule Hologram.Realtime.HandshakeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.Handshake

  alias Hologram.Realtime.Handshake

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(Handshake)
    start_supervised!(Handshake)

    :ok
  end

  describe "insert/4" do
    test "stashes the handshake entry in ETS with the identity tuple flattened" do
      insert(
        "test-handshake-id",
        [{{:room_a, "page"}, "test-user-id"}],
        {"test-instance-id", "test-session-id", "test-user-id"},
        1_700_000_000_000
      )

      assert :ets.lookup(ets_table_name(), "test-handshake-id") == [
               {
                 "test-handshake-id",
                 [{{:room_a, "page"}, "test-user-id"}],
                 "test-instance-id",
                 "test-session-id",
                 "test-user-id",
                 1_700_000_000_000
               }
             ]
    end

    test "broadcasts the insert on the gossip topic with the flattened wire shape" do
      :ok = Phoenix.PubSub.subscribe(Hologram.PubSub, gossip_topic())

      insert(
        "test-handshake-id",
        [{{:room_a, "page"}, "test-user-id"}],
        {"test-instance-id", "test-session-id", "test-user-id"},
        1_700_000_000_000
      )

      assert_receive {
        :insert,
        "test-handshake-id",
        [{{:room_a, "page"}, "test-user-id"}],
        "test-instance-id",
        "test-session-id",
        "test-user-id",
        1_700_000_000_000
      }
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

  describe "{:insert, ...} gossip" do
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

  describe "{:sync_request, ...} handling" do
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
