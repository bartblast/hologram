defmodule HologramClusterTests.CommandSubscriptionTest do
  use HologramClusterTests.TestCase, async: false

  alias Hologram.Realtime
  alias Hologram.Realtime.SubscriptionRegistry

  @channel {:room, :command}

  # Bounded at 100 x 100ms: the binding lands within a round trip when routing works, so
  # ten seconds without it is a broken premise, not slowness.
  @binding_attempts 100

  setup do
    [sse_peer, other_peer] = peers = start_peers(2)
    start_supervised!({Proxy, upstreams: Enum.map(peers, & &1.port)})
    await_pubsub_convergence(peers)

    [other_peer: other_peer, sse_peer: sse_peer]
  end

  for placement <- [:colocated, :remote] do
    @placement placement
    @feature_name "subscribing from a boot-time command delivers broadcasts " <>
                    "(command #{placement} to the stream)"

    feature @feature_name,
            %{session: session, sse_peer: sse_peer, other_peer: other_peer} do
      placement = @placement
      policy = placement_policy(placement, sse_peer, other_peer)
      token = Proxy.register_policy(policy)

      session =
        session
        |> visit("/external")
        |> set_cookie(Proxy.route_cookie(), token)
        |> visit("/command-subscribe")

      wait_for_channel_binding(sse_peer, @channel)

      Realtime.broadcast_action(@channel, :show, message: "delivered across the cluster")

      assert_text(session, "delivered across the cluster")

      if placement == :remote do
        # The premise, not assumed but proven: the command was served by a different
        # upstream than the stream, and the connection lives on the stream's peer only.
        log = Proxy.log()

        command_upstreams =
          for entry <- log, entry.path == "/hologram/command", uniq: true, do: entry.upstream

        stream_upstreams =
          for entry <- log, entry.path == "/hologram/sse", uniq: true, do: entry.upstream

        assert command_upstreams == [other_peer.port]
        assert stream_upstreams == [sse_peer.port]

        assert registry_entries(sse_peer) != []
        assert registry_entries(other_peer) == []
      end
    end
  end

  # The 992-specific placement vocabulary lives here, in the tenant test - the proxy knows
  # only the generic policy contract.
  defp placement_policy(:colocated, sse_peer, _other_peer) do
    fn _request_facts, _cluster_facts -> sse_peer.port end
  end

  defp placement_policy(:remote, sse_peer, other_peer) do
    fn %{path: path}, _cluster_facts ->
      if String.starts_with?(path, "/hologram/sse") do
        sse_peer.port
      else
        other_peer.port
      end
    end
  end

  defp registry_entries(peer) do
    table = rpc(peer, SubscriptionRegistry, :ets_table_name, [])
    rpc(peer, :ets, :tab2list, [table])
  end

  defp wait_for_channel_binding(peer, channel, attempt \\ 1)

  defp wait_for_channel_binding(peer, channel, attempt) when attempt > @binding_attempts do
    raise "no binding on #{inspect(channel)} ever appeared on #{inspect(peer.node)}"
  end

  defp wait_for_channel_binding(peer, channel, attempt) do
    bound? =
      peer
      |> registry_entries()
      |> Enum.any?(fn {_instance_id, entry} ->
        Enum.any?(entry.bindings, fn {{bound_channel, _cid}, _user_id} ->
          bound_channel == channel
        end)
      end)

    if bound? do
      :ok
    else
      Process.sleep(100)
      wait_for_channel_binding(peer, channel, attempt + 1)
    end
  end
end
