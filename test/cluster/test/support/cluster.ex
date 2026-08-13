defmodule HologramClusterTests.Cluster do
  @moduledoc """
  Starts and manages the peer nodes that run app instances for cluster tests.

  The test runner itself serves no app traffic - every app instance lives on a
  peer node, so peers can be stopped, restarted or added mid-test. All peers run
  on loopback from this project's own build.
  """

  @app :hologram_cluster_tests

  # Peers are bare BEAM nodes without Mix, so application env does not come from the
  # config files - it is copied over from this node before the app starts.
  @copied_env_apps [:hologram, :logger, :phoenix, :phoenix_pubsub, @app]

  # 50ms between attempts, so convergence gets ~10s before the premise is declared
  # broken. Local pg merges within peer boot (measured), making every attempt past
  # the first few already a bad sign.
  @convergence_attempts 200

  @cookie :hologram_cluster_tests

  # Orchestrator default is 4003 (never bound - its endpoint runs with server: false)
  # and the proxy owns 4005, so peers live in their own range above both.
  @base_port 4010

  @doc """
  Blocks until a broadcast published on each of the given peers reaches this
  node, proving the PubSub groups of all involved nodes have merged. Returns
  `:ok`, or raises when a peer's broadcasts never arrive within the attempt
  budget.

  Group membership propagates asynchronously after nodes connect, so a
  broadcast published before the merge is silently lost - a test asserting
  delivery before this gate can pass or fail on boot timing alone.
  """
  @spec await_pubsub_convergence([map]) :: :ok
  def await_pubsub_convergence(peers) do
    topic = "hologram_cluster_tests:convergence:#{:erlang.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

    Enum.each(peers, &await_peer_convergence(&1, topic, 1))

    Phoenix.PubSub.unsubscribe(Hologram.PubSub, topic)
    flush_convergence_messages()
  end

  @doc """
  Stops the given peer and starts a fresh one under the same name and port.
  Returns the new peer map.

  The replacement is a brand new BEAM instance: empty ETS, empty registries,
  re-run boot syncs - the same shape as an app instance replaced during a
  deploy.
  """
  @spec restart_peer(map) :: map
  def restart_peer(peer) do
    stop_peer(peer)
    start_peer(peer.index)
  end

  @doc """
  Calls `module.fun(args)` on the given peer (or node) and returns the result.
  Raises when the call cannot be made at all - a dead or unreachable node is a
  broken test premise, not a result to adapt to.
  """
  @spec rpc(map | node, module, atom, list) :: any
  def rpc(%{node: node}, module, fun, args), do: rpc(node, module, fun, args)

  def rpc(node, module, fun, args) when is_atom(node) do
    case :rpc.call(node, module, fun, args) do
      {:badrpc, reason} ->
        raise "rpc #{inspect(module)}.#{fun}/#{length(args)} to #{inspect(node)} failed: " <>
                inspect(reason)

      result ->
        result
    end
  end

  @doc """
  Starts a single peer node named `peer<index>` on loopback, boots the app on
  it, and returns a peer map (`:index`, `:node`, `:pid`, `:port`).

  The framework's environment is passed to the peer explicitly
  (`HOLOGRAM_ENV=test`, `HOLOGRAM_START=1`) - without it the peer's env
  detection falls back to "is ExUnit running", concludes `:dev`, and dies
  starting the dev-only live-reload watcher. The peer gets this node's code
  path minus Mix's ebin: with Mix loadable but not started, the framework's app
  resolution would die on `Mix.ProjectStack`, and without it the release-style
  resolution from loaded applications takes over. Application env is copied for
  the apps that need it, with the endpoint flipped to `server: true` on the
  peer's own port.

  The peer is linked to the calling process, so peers a test starts die with
  it.
  """
  @spec start_peer(pos_integer) :: map
  def start_peer(index) do
    # Peer names form a bounded set (one per index a suite ever uses), so runtime atom
    # creation is safe here.
    # credo:disable-for-lines:3 Credo.Check.Warning.UnsafeToAtom
    {:ok, pid, node} =
      :peer.start_link(%{
        name: :"peer#{index}",
        host: ~c"127.0.0.1",
        args: [~c"-setcookie", Atom.to_charlist(@cookie)],
        env: [
          {~c"HOLOGRAM_ENV", ~c"test"},
          {~c"HOLOGRAM_START", ~c"1"}
        ]
      })

    port = @base_port + index

    rpc(node, :code, :add_paths, [code_paths_without_mix()])
    copy_app_env(node, port)
    rpc(node, Application, :load, [@app])
    {:ok, _apps} = rpc(node, Application, :ensure_all_started, [@app])

    %{index: index, node: node, pid: pid, port: port}
  end

  @doc """
  Starts `count` peers with consecutive indexes and returns their peer maps.
  """
  @spec start_peers(pos_integer) :: [map]
  def start_peers(count) do
    Enum.map(1..count, &start_peer/1)
  end

  @doc """
  Stops the given peer and returns once the node has left the cluster, so its
  name and port are free for a replacement.
  """
  @spec stop_peer(map) :: :ok
  def stop_peer(peer) do
    :peer.stop(peer.pid)
    await_node_down(peer.node, 1)
  end

  defp await_node_down(node, attempt) when attempt > @convergence_attempts do
    raise "#{inspect(node)} did not leave the cluster after being stopped"
  end

  defp await_node_down(node, attempt) do
    if node in Node.list(:connected) do
      Process.sleep(10)
      await_node_down(node, attempt + 1)
    else
      :ok
    end
  end

  defp await_peer_convergence(peer, _topic, attempt) when attempt > @convergence_attempts do
    raise "PubSub groups never converged with #{inspect(peer.node)}"
  end

  defp await_peer_convergence(peer, topic, attempt) do
    rpc(peer, Phoenix.PubSub, :broadcast, [
      Hologram.PubSub,
      topic,
      {:pubsub_converged, peer.node}
    ])

    node = peer.node

    receive do
      {:pubsub_converged, ^node} -> :ok
    after
      50 -> await_peer_convergence(peer, topic, attempt + 1)
    end
  end

  defp code_paths_without_mix do
    Enum.reject(:code.get_path(), fn path ->
      path
      |> List.to_string()
      |> String.ends_with?("/mix/ebin")
    end)
  end

  defp copy_app_env(node, port) do
    for app <- @copied_env_apps, {key, value} <- Application.get_all_env(app) do
      rpc(node, Application, :put_env, [app, key, value])
    end

    endpoint_config =
      @app
      |> Application.fetch_env!(HologramClusterTestsWeb.Endpoint)
      |> Keyword.put(:http, ip: {127, 0, 0, 1}, port: port)
      |> Keyword.put(:server, true)

    rpc(node, Application, :put_env, [@app, HologramClusterTestsWeb.Endpoint, endpoint_config])
  end

  # Late broadcasts from earlier attempts must not linger, or a test's later
  # refute_receive could trip on them.
  defp flush_convergence_messages do
    receive do
      {:pubsub_converged, _node} -> flush_convergence_messages()
    after
      0 -> :ok
    end
  end
end
