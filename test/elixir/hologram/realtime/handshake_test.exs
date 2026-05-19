defmodule Hologram.Realtime.HandshakeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.Handshake

  alias Hologram.Realtime.Handshake

  setup do
    wait_for_process_cleanup(Handshake)
    start_supervised!(Handshake)

    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

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
end
