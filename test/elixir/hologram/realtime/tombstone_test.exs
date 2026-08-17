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

  describe "handle {:purge, ...}" do
    test "deletes the tombstone for the key" do
      key = {{:user, 7}, :notifications, "c1"}
      :ok = insert(key, @timestamp)

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        gossip_topic(),
        {:purge, key, @timestamp + 10}
      )

      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == []
    end

    # A peer answers a sync request out of its own table, which can still hold the
    # tombstone this purge cancelled. The purge has to outrank it on arrival, or the
    # re-grant it recorded is undone.
    test "keeps a purged key out when a later sync reply carries the cancelled tombstone" do
      key = {{:user, 7}, :notifications, "c1"}

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        gossip_topic(),
        {:purge, key, @timestamp + 10}
      )

      :sys.get_state(Tombstone)

      send(Process.whereis(Tombstone), {:sync_reply, [{key, @timestamp}]})

      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == []
    end

    # The purge cancels the revocation it superseded, not one that came after it.
    test "admits a revocation newer than the purge that preceded it" do
      key = {{:user, 7}, :notifications, "c1"}

      Phoenix.PubSub.broadcast(Hologram.PubSub, gossip_topic(), {:purge, key, @timestamp})

      :sys.get_state(Tombstone)

      send(Process.whereis(Tombstone), {:sync_reply, [{key, @timestamp + 10}]})

      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == [{key, @timestamp + 10}]
    end

    # A node that has not been upgraded still gossips the timeless shape.
    test "accepts a purge from a peer that sends no time with it" do
      key = {{:user, 7}, :notifications, "c1"}
      :ok = insert(key, @timestamp)

      Phoenix.PubSub.broadcast(Hologram.PubSub, gossip_topic(), {:purge, key})

      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == []
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

  describe "handle {:sync_reply, ...}" do
    test "merges a peer's tombstones into ETS" do
      key = {{:user, 7}, :notifications, "c1"}

      send(Process.whereis(Tombstone), {:sync_reply, [{key, @timestamp}]})

      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == [{key, @timestamp}]
    end

    # A reply arrives through the same per-entry rule as a gossiped insert, so a peer
    # holding an older record for a key cannot roll this node's back.
    test "keeps the later timestamp when a reply carries an older entry for an existing key" do
      key = {{:user, 7}, :notifications, "c1"}
      :ok = insert(key, @timestamp + 10)

      send(Process.whereis(Tombstone), {:sync_reply, [{key, @timestamp}]})

      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == [{key, @timestamp + 10}]
    end
  end

  describe "handle {:nodeup, ...}" do
    # A boot-time request only reaches peers this node can already see. Watching joins is
    # what lets a store that booted into a still-forming cluster catch up afterwards.
    test "asks the joining node for what it holds" do
      Phoenix.PubSub.subscribe(Hologram.PubSub, gossip_topic())

      tombstone_pid = Process.whereis(Tombstone)

      send(tombstone_pid, {:nodeup, node()})

      assert_receive {:sync_request, ^tombstone_pid}
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

    # The reason the sync request does not wait: a node that is accepting requests has
    # to serve them. Against a blocking boot sync this call exits on its own timeout.
    test "serves an insert straight away, without waiting on peers" do
      :ok = stop_supervised(Tombstone)

      start_supervised!(Tombstone)

      key = {{:user, 7}, :notifications, "c1"}

      assert insert(key, @timestamp) == :ok
      assert :ets.lookup(ets_table_name(), key) == [{key, @timestamp}]
    end

    test "starts with an empty table when no peer replies" do
      :ok = stop_supervised(Tombstone)

      start_supervised!(Tombstone)

      # A synchronous call returns only once init/1 has run.
      :sys.get_state(Tombstone)

      assert :ets.tab2list(ets_table_name()) == []
    end

    # Asking is per connected node, so there is nobody to ask here. That a peer receives
    # the request and answers it is cluster-suite territory - what this pins is that
    # starting up asks without waiting, and stays open to gossip afterwards.
    test "still merges a steady-state {:insert, ...} a peer publishes after starting" do
      :ok = stop_supervised(Tombstone)

      start_supervised!(Tombstone)

      key = {{:user, 7}, :notifications, "c1"}

      Phoenix.PubSub.broadcast(Hologram.PubSub, gossip_topic(), {:insert, key, @timestamp})

      wait_until(fn -> :ets.lookup(ets_table_name(), key) == [{key, @timestamp}] end)

      assert :ets.lookup(ets_table_name(), key) == [{key, @timestamp}]
    end
  end
end
