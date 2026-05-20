defmodule Hologram.Realtime.TombstoneTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.Tombstone

  alias Hologram.Realtime.Tombstone

  @timestamp 1_700_000_000_000

  defp spawn_peer(test_pid, on_sync_request) do
    spawn_link(fn ->
      Phoenix.PubSub.subscribe(Hologram.PubSub, gossip_topic())
      send(test_pid, :peer_ready)

      receive do
        {:sync_request, requester_pid} -> on_sync_request.(requester_pid)
      end
    end)
  end

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(Tombstone)
    start_supervised!({Tombstone, boot_sync_timeout_ms: 0})

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

  describe "purge_for_instance/1" do
    test "removes both binding-level and channel-wide tombstones for the target instance" do
      instance = {:instance, "instance-a"}
      binding_key = {instance, :notifications, "c1"}
      channel_key = {instance, :notifications}

      :ok = insert(binding_key, @timestamp)
      :ok = insert(channel_key, @timestamp)

      :ok = purge_for_instance("instance-a")

      assert :ets.lookup(ets_table_name(), binding_key) == []
      assert :ets.lookup(ets_table_name(), channel_key) == []
    end

    test "leaves tombstones for other instances untouched" do
      target_key = {{:instance, "instance-a"}, :notifications, "c1"}
      other_key = {{:instance, "instance-b"}, :notifications, "c1"}

      :ok = insert(target_key, @timestamp)
      :ok = insert(other_key, @timestamp)

      :ok = purge_for_instance("instance-a")

      assert :ets.lookup(ets_table_name(), target_key) == []
      assert :ets.lookup(ets_table_name(), other_key) == [{other_key, @timestamp}]
    end

    test "leaves tombstones at non-instance identity levels untouched" do
      instance_key = {{:instance, "instance-a"}, :notifications, "c1"}
      session_key = {{:session, "session-1"}, :notifications, "c1"}
      user_key = {{:user, 7}, :notifications, "c1"}

      :ok = insert(instance_key, @timestamp)
      :ok = insert(session_key, @timestamp)
      :ok = insert(user_key, @timestamp)

      :ok = purge_for_instance("instance-a")

      assert :ets.lookup(ets_table_name(), instance_key) == []
      assert :ets.lookup(ets_table_name(), session_key) == [{session_key, @timestamp}]
      assert :ets.lookup(ets_table_name(), user_key) == [{user_key, @timestamp}]
    end

    test "is a no-op when no tombstones match" do
      assert :ok = purge_for_instance("unknown-instance")
    end

    test "broadcasts the purge on the gossip topic" do
      :ok = Phoenix.PubSub.subscribe(Hologram.PubSub, gossip_topic())

      purge_for_instance("instance-a")

      assert_receive {:purge_for_instance, "instance-a"}
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
    test "deletes the matching entry from local ETS" do
      key = {{:user, 7}, :notifications, "c1"}
      :ok = insert(key, @timestamp)

      Phoenix.PubSub.broadcast(Hologram.PubSub, gossip_topic(), {:purge, key})
      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == []
    end

    test "is a no-op when no entry matches the key" do
      key = {{:user, 7}, :notifications, "c1"}

      Phoenix.PubSub.broadcast(Hologram.PubSub, gossip_topic(), {:purge, key})
      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == []
    end
  end

  describe "handle {:purge_for_instance, ...}" do
    test "removes both binding-level and channel-wide tombstones for the target instance" do
      binding_key = {{:instance, "instance-a"}, :notifications, "c1"}
      channel_key = {{:instance, "instance-a"}, :notifications}

      :ok = insert(binding_key, @timestamp)
      :ok = insert(channel_key, @timestamp)

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        gossip_topic(),
        {:purge_for_instance, "instance-a"}
      )

      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), binding_key) == []
      assert :ets.lookup(ets_table_name(), channel_key) == []
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

    test "merges entries from a peer that replies to the boot-sync request" do
      :ok = stop_supervised(Tombstone)

      test_pid = self()
      key = {{:user, 7}, :notifications, "c1"}
      peer_entry = {key, @timestamp}

      spawn_peer(test_pid, fn requester_pid ->
        send(requester_pid, {:sync_reply, [peer_entry]})
      end)

      assert_receive :peer_ready

      start_supervised!({Tombstone, boot_sync_timeout_ms: 200})

      assert :ets.lookup(ets_table_name(), key) == [peer_entry]
    end

    test "returns with an empty table when no peers reply before the timeout" do
      :ok = stop_supervised(Tombstone)

      start_supervised!({Tombstone, boot_sync_timeout_ms: 50})

      assert :ets.tab2list(ets_table_name()) == []
    end

    test "still receives a steady-state {:insert, ...} a peer publishes after the sync_request" do
      :ok = stop_supervised(Tombstone)

      test_pid = self()
      key = {{:user, 7}, :notifications, "c1"}

      spawn_peer(test_pid, fn _requester_pid ->
        Phoenix.PubSub.broadcast(Hologram.PubSub, gossip_topic(), {:insert, key, @timestamp})
      end)

      assert_receive :peer_ready

      start_supervised!({Tombstone, boot_sync_timeout_ms: 50})

      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), key) == [{key, @timestamp}]
    end

    test "takes the later timestamp when multiple peers reply with the same key at different timestamps" do
      :ok = stop_supervised(Tombstone)

      test_pid = self()
      key = {{:user, 7}, :notifications, "c1"}

      spawn_peer(test_pid, fn requester_pid ->
        send(requester_pid, {:sync_reply, [{key, @timestamp}]})
      end)

      spawn_peer(test_pid, fn requester_pid ->
        send(requester_pid, {:sync_reply, [{key, @timestamp + 10}]})
      end)

      assert_receive :peer_ready
      assert_receive :peer_ready

      start_supervised!({Tombstone, boot_sync_timeout_ms: 200})

      assert :ets.lookup(ets_table_name(), key) == [{key, @timestamp + 10}]
    end

    test "subsequent gossip lands in ETS after boot-sync completes" do
      :ok = stop_supervised(Tombstone)

      test_pid = self()
      synced_key = {{:user, 7}, :notifications, "c1"}
      gossip_key = {{:user, 7}, :notifications, "c2"}

      spawn_peer(test_pid, fn requester_pid ->
        send(requester_pid, {:sync_reply, [{synced_key, @timestamp}]})
      end)

      assert_receive :peer_ready

      start_supervised!({Tombstone, boot_sync_timeout_ms: 50})

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        gossip_topic(),
        {:insert, gossip_key, @timestamp + 1}
      )

      :sys.get_state(Tombstone)

      assert :ets.lookup(ets_table_name(), synced_key) == [{synced_key, @timestamp}]
      assert :ets.lookup(ets_table_name(), gossip_key) == [{gossip_key, @timestamp + 1}]
    end
  end
end
