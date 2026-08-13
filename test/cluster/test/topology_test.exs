defmodule HologramClusterTests.TopologyTest do
  use HologramClusterTests.TestCase, async: false

  alias HologramClusterTests.HTTPClient

  # The smoke test for the premises every cluster test stands on. When the cluster or the
  # proxy regresses to something a single node could satisfy, this file fails by name -
  # instead of the tenant tests passing vacuously against a one-node "cluster".

  setup do
    peers = start_peers(2)
    start_supervised!({Proxy, upstreams: Enum.map(peers, & &1.port)})
    await_pubsub_convergence(peers)

    [peers: peers]
  end

  test "both peers are visible and their PubSub groups have merged", %{peers: peers} do
    visible_nodes = Node.list(:connected)

    assert Enum.all?(peers, &(&1.node in visible_nodes))
    assert await_pubsub_convergence(peers) == :ok
  end

  test "the proxy reaches every upstream under the round-robin default", %{peers: peers} do
    proxy_port = Application.fetch_env!(:hologram_cluster_tests, :proxy_port)

    statuses =
      Enum.map(1..4, fn _request_number ->
        HTTPClient.get("http://127.0.0.1:#{proxy_port}/external").status
      end)

    assert statuses == [200, 200, 200, 200]

    serving_upstreams =
      Proxy.log()
      |> Enum.map(& &1.upstream)
      |> Enum.uniq()
      |> Enum.sort()

    expected_upstreams =
      peers
      |> Enum.map(& &1.port)
      |> Enum.sort()

    assert serving_upstreams == expected_upstreams
  end

  feature "a browser loads a page through the proxy", %{session: session} do
    session
    |> visit("/init-subscribe")
    |> assert_text("Received:")
  end
end
