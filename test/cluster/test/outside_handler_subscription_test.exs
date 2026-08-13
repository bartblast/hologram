defmodule HologramClusterTests.OutsideHandlerSubscriptionTest do
  use HologramClusterTests.TestCase, async: false

  import HologramClusterTests.RealtimeHelpers

  alias Hologram.Realtime

  @channel {:room, :granted}

  setup do
    [sse_peer, other_peer] = peers = start_peers(2)
    start_supervised!({Proxy, upstreams: Enum.map(peers, & &1.port)})
    await_pubsub_convergence(peers)

    [other_peer: other_peer, sse_peer: sse_peer]
  end

  feature "a grant issued on a node not holding the connection reaches the tab",
          %{session: session, sse_peer: sse_peer, other_peer: other_peer} do
    # Pin the whole tab to one peer, so the grant below provably originates elsewhere.
    token = Proxy.register_policy(fn _request_facts, _cluster_facts -> sse_peer.port end)

    session =
      session
      |> visit("/external")
      |> set_cookie(Proxy.route_cookie(), token)
      |> visit("/plain")

    wait_for_connection(sse_peer)
    instance_id = instance_id_of(session)

    # Both the grant and the broadcast run on the peer that does NOT hold the
    # connection - a background job landing on an arbitrary cluster node.
    rpc(other_peer, Realtime, :subscribe, [{:instance, instance_id}, @channel, "page"])

    wait_for_channel_binding(sse_peer, @channel)
    wait_for_channel_subscriber(sse_peer, @channel)

    rpc(other_peer, Realtime, :broadcast_action, [
      @channel,
      :show,
      [message: "granted across the cluster"]
    ])

    assert_text(session, "granted across the cluster")

    # The premise, proven: the binding lives on the peer holding the stream, and the
    # granting peer holds nothing.
    assert registry_entries(other_peer) == []
  end
end
