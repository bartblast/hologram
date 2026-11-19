defmodule HologramClusterTests.ClusterTest do
  use ExUnit.Case, async: false

  import HologramClusterTests.Cluster

  alias HologramClusterTests.HTTPClient

  # The picks go up the run's block and start over after its last port.
  defp next_free_port do
    first_port = proxy_port() + 1
    last_port = proxy_port() + 126

    case free_port() do
      ^last_port -> first_port
      port -> port + 1
    end
  end

  describe "await_pubsub_convergence/1" do
    test "returns :ok once every peer's broadcast reaches this node" do
      peers = start_peers(2)

      assert await_pubsub_convergence(peers) == :ok
    end
  end

  describe "free_port/0" do
    test "returns a port of the run's block, after the proxy's, that nothing listens on" do
      port = free_port()

      assert port in (proxy_port() + 1)..(proxy_port() + 126)
      assert {:ok, socket} = :gen_tcp.listen(port, ip: {127, 0, 0, 1})

      :gen_tcp.close(socket)
    end

    test "returns another port each time" do
      ports = Enum.map(1..10, fn _index -> free_port() end)

      assert Enum.uniq(ports) == ports
    end

    test "skips a port something listens on" do
      next_port = next_free_port()

      # With reuseaddr, so a connection that just closed on the port can't refuse the listen.
      {:ok, socket} = :gen_tcp.listen(next_port, ip: {127, 0, 0, 1}, reuseaddr: true)

      port = free_port()

      :gen_tcp.close(socket)

      assert port != next_port
    end

    test "skips a port something listens on over IPv6 alone" do
      next_port = next_free_port()

      case :gen_tcp.listen(next_port, [:inet6, ip: {0, 0, 0, 0, 0, 0, 0, 1}, reuseaddr: true]) do
        {:ok, socket} ->
          port = free_port()

          :gen_tcp.close(socket)

          assert port != next_port

        # A machine without IPv6 has no such listeners.
        {:error, reason} ->
          assert reason in [:eaddrnotavail, :eafnosupport, :eprotonosupport]
      end
    end
  end

  describe "proxy_port/0" do
    test "returns the port after the one this run holds as its claim on the block" do
      claim_port = proxy_port() - 1

      assert rem(claim_port - 20_000, 128) == 0
      assert :gen_tcp.listen(claim_port, ip: {127, 0, 0, 1}) == {:error, :eaddrinuse}
    end

    test "returns the same port each time" do
      assert proxy_port() == proxy_port()
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

    test "starts the replacement with the peer's own options" do
      # The options are what make a peer a production instance against another database -
      # a replacement started without them is a different peer under the same name.
      peer =
        start_peer(1,
          app_env: [{:hologram, :restart_marker, :carried_over}],
          boot_app: false,
          hologram_env: "prod"
        )

      new_peer = restart_peer(peer)

      assert rpc(new_peer, System, :get_env, ["HOLOGRAM_ENV"]) == "prod"
      assert rpc(new_peer, Application, :get_env, [:hologram, :restart_marker]) == :carried_over
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

      message = "rpc Node.self/0 to #{inspect(peer.node)} failed"

      assert_raise RuntimeError, ~r/#{Regex.escape(message)}/, fn ->
        rpc(peer, Node, :self, [])
      end
    end
  end

  describe "start_peers/1" do
    test "names each peer after its index and this BEAM's OS pid" do
      peers = start_peers(2)

      os_pid = System.pid()

      assert Enum.map(peers, &Atom.to_string(&1.node)) == [
               "peer1_#{os_pid}@127.0.0.1",
               "peer2_#{os_pid}@127.0.0.1"
             ]
    end

    test "gives each peer a port of its own from the run's block" do
      [peer_1, peer_2] = start_peers(2)

      block_ports = (proxy_port() + 1)..(proxy_port() + 126)

      assert peer_1.port in block_ports
      assert peer_2.port in block_ports
      assert peer_1.port != peer_2.port
    end

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
