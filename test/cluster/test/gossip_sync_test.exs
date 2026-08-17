defmodule HologramClusterTests.GossipSyncTest do
  use ExUnit.Case, async: false

  import HologramClusterTests.Cluster

  alias Hologram.Realtime.Handshake
  alias Hologram.Realtime.Tombstone

  @attempts 100

  # A node that boots asks its peers for what they hold and merges the replies whenever
  # they land, rather than waiting out a window. Everything else covering that is
  # single-VM, with a spawned process standing in for the peer - this is the only place
  # a real node catches up from a real node over distribution.
  #
  # The no-peers case is not here and cannot be: a node started by `:peer` is connected
  # to the node that started it, and this suite's own node runs the framework too, so
  # there is always a peer holding state to answer. That case is unit-tested instead.
  describe "a booting node catching up from its peers" do
    test "takes on a handshake a peer stashed before it started" do
      [holder, restarting] = peers = start_peers(2)
      await_pubsub_convergence(peers)

      handshake_id = "cluster-sync-handshake-id"
      expires_at = System.system_time(:millisecond) + 60_000

      rpc(holder, Handshake, :insert, [
        handshake_id,
        [],
        {"cluster-instance-id", "cluster-session-id", "cluster-user-id"},
        expires_at
      ])

      booted = restart_peer(restarting)
      await_pubsub_convergence([holder, booted])

      assert wait_for_handshake(booted, handshake_id) ==
               [
                 {handshake_id, [], "cluster-instance-id", "cluster-session-id",
                  "cluster-user-id", expires_at}
               ]
    end

    test "takes on a tombstone a peer holds before it started" do
      [holder, restarting] = peers = start_peers(2)
      await_pubsub_convergence(peers)

      key = {{:user, "cluster-sync-user"}, :notifications, "page"}
      created_at = System.system_time(:millisecond)

      rpc(holder, Tombstone, :insert, [key, created_at])

      booted = restart_peer(restarting)
      await_pubsub_convergence([holder, booted])

      assert wait_for_tombstone(booted, key) == [{key, created_at}]
    end
  end

  defp wait_for_handshake(peer, handshake_id, attempt \\ 1)

  defp wait_for_handshake(peer, handshake_id, attempt) when attempt > @attempts do
    raise "handshake #{inspect(handshake_id)} never synced to #{inspect(peer.node)}"
  end

  defp wait_for_handshake(peer, handshake_id, attempt) do
    case rpc(peer, :ets, :lookup, [Handshake.ets_table_name(), handshake_id]) do
      [] ->
        Process.sleep(100)
        wait_for_handshake(peer, handshake_id, attempt + 1)

      entries ->
        entries
    end
  end

  defp wait_for_tombstone(peer, key, attempt \\ 1)

  defp wait_for_tombstone(peer, key, attempt) when attempt > @attempts do
    raise "tombstone #{inspect(key)} never synced to #{inspect(peer.node)}"
  end

  defp wait_for_tombstone(peer, key, attempt) do
    case rpc(peer, :ets, :lookup, [Tombstone.ets_table_name(), key]) do
      [] ->
        Process.sleep(100)
        wait_for_tombstone(peer, key, attempt + 1)

      entries ->
        entries
    end
  end
end
