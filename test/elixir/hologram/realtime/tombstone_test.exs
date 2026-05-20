defmodule Hologram.Realtime.TombstoneTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.Tombstone

  alias Hologram.Realtime.Tombstone

  @timestamp 1_700_000_000_000

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(Tombstone)
    start_supervised!(Tombstone)

    :ok
  end

  describe "insert/2" do
    test "writes a binding-level tombstone {identity, channel, cid} to ETS with the timestamp" do
      key = {{:user, 7}, :notifications, "c1"}
      :ok = insert(key, @timestamp)

      assert :ets.lookup(ets_table_name(), key) == [{key, @timestamp}]
    end

    test "writes a channel-wide tombstone {identity, channel} to ETS with the timestamp" do
      key = {{:user, 7}, :notifications}
      :ok = insert(key, @timestamp)

      assert :ets.lookup(ets_table_name(), key) == [{key, @timestamp}]
    end

    test "binding-level and channel-wide tombstones at the same identity level coexist" do
      binding_key = {{:user, 7}, :notifications, "c1"}
      channel_key = {{:user, 7}, :notifications}

      :ok = insert(binding_key, @timestamp)
      :ok = insert(channel_key, @timestamp + 1)

      assert :ets.lookup(ets_table_name(), binding_key) == [{binding_key, @timestamp}]
      assert :ets.lookup(ets_table_name(), channel_key) == [{channel_key, @timestamp + 1}]
    end

    test "broadcasts the insert on the gossip topic" do
      :ok = Phoenix.PubSub.subscribe(Hologram.PubSub, gossip_topic())
      key = {{:user, 7}, :notifications, "c1"}

      insert(key, @timestamp)

      assert_receive {:insert, ^key, @timestamp}
    end
  end

  describe "handle {:insert, ...}" do
    test "merges a peer-broadcast {:insert, ...} into local ETS" do
      key = {{:user, 7}, :notifications, "c1"}

      Phoenix.PubSub.broadcast(Hologram.PubSub, gossip_topic(), {:insert, key, @timestamp})

      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == [{key, @timestamp}]
    end

    test "keeps the later timestamp when an older peer insert arrives for an existing key" do
      key = {{:user, 7}, :notifications, "c1"}
      :ok = insert(key, @timestamp + 10)

      Phoenix.PubSub.broadcast(Hologram.PubSub, gossip_topic(), {:insert, key, @timestamp})

      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == [{key, @timestamp + 10}]
    end

    test "takes the later timestamp when a newer peer insert arrives for an existing key" do
      key = {{:user, 7}, :notifications, "c1"}
      :ok = insert(key, @timestamp)

      Phoenix.PubSub.broadcast(Hologram.PubSub, gossip_topic(), {:insert, key, @timestamp + 10})

      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == [{key, @timestamp + 10}]
    end
  end

  describe "handle :sweep_expired" do
    test "deletes entries whose created_at is older than the TTL" do
      key = {{:user, 7}, :notifications, "c1"}
      :ok = insert(key, @timestamp)

      send(Tombstone, :sweep_expired)
      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == []
    end

    test "preserves entries within the TTL" do
      key = {{:user, 7}, :notifications, "c1"}
      now = System.system_time(:millisecond)
      :ok = insert(key, now)

      send(Tombstone, :sweep_expired)
      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == [{key, now}]
    end
  end

  describe "handle {:sync_request, ...}" do
    test "replies to the requester via direct send/2 with the current ETS dump" do
      key = {{:user, 7}, :notifications, "c1"}
      :ok = insert(key, @timestamp)

      Phoenix.PubSub.broadcast(Hologram.PubSub, gossip_topic(), {:sync_request, self()})

      assert_receive {:sync_reply, [{^key, @timestamp}]}
    end

    test "replies with an empty list when the ETS table is empty" do
      Phoenix.PubSub.broadcast(Hologram.PubSub, gossip_topic(), {:sync_request, self()})

      assert_receive {:sync_reply, []}
    end
  end

  describe "start_link/1" do
    test "starts under a supervisor and registers itself by module name" do
      assert process_name_registered?(Tombstone)
    end

    test "creates the backing ETS table" do
      assert :ets.info(ets_table_name()) != :undefined
    end
  end
end
