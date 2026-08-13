defmodule HologramClusterTests.ClusterTest do
  use ExUnit.Case, async: false

  import HologramClusterTests.Cluster

  alias HologramClusterTests.HTTPClient

  describe "await_pubsub_convergence/1" do
    test "returns :ok once every peer's broadcast reaches this node" do
      peers = start_peers(2)

      assert await_pubsub_convergence(peers) == :ok
    end
  end

  describe "restart_peer/1" do
    test "replaces the peer with a fresh app instance under the same name and port" do
      [peer] = start_peers(1)
      registry_pid = rpc(peer, Process, :whereis, [Hologram.Realtime.SubscriptionRegistry])

      new_peer = restart_peer(peer)

      assert new_peer.node == peer.node
      assert new_peer.port == peer.port

      new_registry_pid =
        rpc(new_peer, Process, :whereis, [Hologram.Realtime.SubscriptionRegistry])

      assert is_pid(new_registry_pid)
      refute new_registry_pid == registry_pid
    end
  end

  describe "rpc/4" do
    test "returns the remote call's result" do
      [peer] = start_peers(1)

      assert rpc(peer, Node, :self, []) == peer.node
    end

    test "raises when the node is not reachable" do
      [peer] = start_peers(1)
      stop_peer(peer)

      assert_raise RuntimeError, ~r/rpc Node.self\/0 to :"peer1@127.0.0.1" failed/, fn ->
        rpc(peer, Node, :self, [])
      end
    end
  end

  describe "start_peers/1" do
    test "starts the requested number of connected peers" do
      peers = start_peers(2)

      visible_nodes = Node.list(:connected)

      assert Enum.all?(peers, &(&1.node in visible_nodes))
    end

    test "boots the app on each peer with its endpoint up" do
      peers = start_peers(2)

      Enum.each(peers, fn peer ->
        endpoint_pid = rpc(peer, Process, :whereis, [HologramClusterTestsWeb.Endpoint])

        assert is_pid(endpoint_pid)
      end)
    end

    test "serves app traffic on each peer's own port" do
      [peer_1, peer_2] = start_peers(2)

      assert HTTPClient.get("http://127.0.0.1:#{peer_1.port}/external").status == 200
      assert HTTPClient.get("http://127.0.0.1:#{peer_2.port}/external").status == 200
    end

    test "enables the framework runtime on the peer through the inherited environment" do
      [peer] = start_peers(1)

      assert is_pid(rpc(peer, Process, :whereis, [Hologram.PubSub]))
      assert is_pid(rpc(peer, Process, :whereis, [Hologram.Realtime.SubscriptionRegistry]))
    end
  end

  describe "stop_peer/1" do
    test "removes the node from the cluster" do
      [peer] = start_peers(1)
      assert peer.node in Node.list(:connected)

      stop_peer(peer)

      refute peer.node in Node.list(:connected)
    end
  end
end
