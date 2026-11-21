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

  # 10ms between attempts, so a stopped node gets the same ~10s to leave the cluster that
  # convergence gets to form it. Both wait on the same distribution layer, and a loaded
  # runner slows shutdown as readily as it slows a merge.
  @node_down_attempts 1_000

  # The run's ports come from one block of this range, which the run claims by listening on
  # the block's first port for as long as its BEAM lives. Another run finds that port taken and
  # claims another block, so two runs never pick the same port, however long a picked port
  # waits for its listener. The OS frees the claim when the BEAM ends, killed or not.
  #
  # The range sits below every OS's ephemeral range, which starts at 32768 on Linux and at
  # 49152 on macOS and Windows, so no outgoing connection takes one of its ports either.
  @port_block_size 128

  @port_block_agent __MODULE__.PortBlock

  @port_range 20_000..32_767

  @doc """
  Blocks until a broadcast published on every node of the cluster (this one and
  each peer) has been delivered to a subscriber on every other node - all
  ordered pairs, not just each peer to this node. Returns `:ok`, or raises
  naming the first pair whose delivery never arrived within the attempt budget.

  Group membership propagates asynchronously and pairwise after nodes connect,
  so peers can converge with this node noticeably before they converge with
  each other - a broadcast between them in that window is silently lost. A test
  asserting delivery before this gate would pass or fail on boot timing alone.
  """
  @spec await_pubsub_convergence([map]) :: :ok
  def await_pubsub_convergence(peers) do
    topic = "hologram_cluster_tests:convergence:#{:erlang.unique_integer([:positive])}"
    nodes = [node() | Enum.map(peers, & &1.node)]

    for receiver_node <- nodes do
      Node.spawn(receiver_node, __MODULE__, :subscribe_and_forward, [topic, self()])
    end

    for sender_node <- nodes, receiver_node <- nodes, sender_node != receiver_node do
      await_pair_convergence(sender_node, receiver_node, topic, 1)
    end

    flush_forwarded_messages()
  end

  @doc """
  Starts the app on the given peer and returns the raw
  `Application.ensure_all_started/1` result.

  A failed boot comes back as `{:error, reason}` rather than raising: a node
  that refuses to start is the observation some scenarios are written to make -
  a database it must not touch, a schema it cannot converge - and the reason
  carries the message being asserted on.
  """
  @spec boot_app(map) :: {:ok, [atom]} | {:error, term}
  def boot_app(peer) do
    rpc(peer, Application, :ensure_all_started, [@app])
  end

  @doc """
  Returns a port nothing listens on, for a peer or a stub server.

  Runs that overlap on one machine must not share ports, so none is fixed. The
  port is the next one of the block of ports this run has claimed, after the
  block's first two, which are the claim itself and the proxy's port. A port
  something else listens on is skipped. After the block's last port the picks
  start over, by which time the peers that had the first ones are long gone.
  """
  @spec free_port() :: pos_integer
  def free_port do
    free_port(1)
  end

  @doc """
  Returns the port of the run's proxy: the second port of the block of ports
  this run has claimed. It stays the same for the whole run, since the browser's
  base URL names it, while the proxy comes and goes with the tests that use it.
  """
  @spec proxy_port() :: pos_integer
  def proxy_port do
    Agent.get(port_block(), & &1.first) + 1
  end

  @doc """
  Stops the given peer and starts a fresh one under the same name, port and
  options. Returns the new peer map.

  The replacement is a brand new BEAM instance: empty ETS, empty registries,
  re-run boot syncs - the same shape as an app instance replaced during a
  deploy. Everything else about it is what it was, so a peer running as a
  production instance against another database comes back as one.
  """
  @spec restart_peer(map) :: map
  def restart_peer(peer) do
    stop_peer(peer)
    start_peer_on_port(peer.index, peer.port, peer.opts)
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
  Starts a single peer node on loopback, boots the app on it, and returns a peer
  map (`:index`, `:node`, `:opts`, `:pid`, `:port`).

  The node is named `peer<index>_<the BEAM's OS pid>` and gets a port from
  `free_port/0`, so runs that overlap on one machine share neither.

  Options:

    * `:hologram_env` - the framework environment the peer runs as, default
      `"test"`. It selects the peer's schema mechanism, so a `"prod"` peer
      applies migrations at boot where a `"test"` one does not.
    * `:app_env` - `{app, key, value}` triples applied after this node's
      application env is copied over, so one peer can be pointed at a different
      database than the orchestrator without touching the orchestrator's own
      config.
    * `:boot_app` - whether to start the app, default `true`. With `false` the
      peer is ready but idle, and `boot_app/1` starts it later - which is what
      lets a test boot several peers at the same instant, or watch a boot fail.

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
  @spec start_peer(pos_integer, keyword) :: map
  def start_peer(index, opts \\ []) do
    start_peer_on_port(index, free_port(), opts)
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

  Stopping a peer that is already gone is not an error: the link may have taken
  it down first, and the wait for the node to leave is the part that matters
  either way.
  """
  @spec stop_peer(map) :: :ok
  def stop_peer(peer) do
    try do
      :peer.stop(peer.pid)
    catch
      :exit, _reason -> :ok
    end

    await_node_down(peer.node, 1)
  end

  @doc """
  Subscribes on the local node's PubSub to `topic` and forwards every received
  message to `forward_to` as `{:forwarded, node(), message}`, until `forward_to`
  dies. Started on a chosen node via `Node.spawn/4`, which is what makes it
  useful: a long-lived subscriber on that node, observable from the caller.
  """
  @spec subscribe_and_forward(String.t(), pid) :: :ok
  def subscribe_and_forward(topic, forward_to) do
    Phoenix.PubSub.subscribe(Hologram.PubSub, topic)
    Process.monitor(forward_to)
    forward_loop(forward_to)
  end

  defp await_node_down(node, attempt) when attempt > @node_down_attempts do
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

  defp await_pair_convergence(sender_node, receiver_node, _topic, attempt)
       when attempt > @convergence_attempts do
    raise "PubSub never converged from #{inspect(sender_node)} to #{inspect(receiver_node)}"
  end

  defp await_pair_convergence(sender_node, receiver_node, topic, attempt) do
    rpc(sender_node, Phoenix.PubSub, :broadcast, [
      Hologram.PubSub,
      topic,
      {:pubsub_converged, sender_node, receiver_node}
    ])

    receive do
      {:forwarded, ^receiver_node, {:pubsub_converged, ^sender_node, ^receiver_node}} -> :ok
    after
      50 -> await_pair_convergence(sender_node, receiver_node, topic, attempt + 1)
    end
  end

  # Probed on every address of both IP versions, so a listener on any of them counts: the
  # browser reaches the proxy through localhost, which may resolve to the IPv6 loopback first.
  # The probes set no reuseaddr, which would let them share a port with a loopback listener.
  # Their sockets are closed again, since the run's claim on the block is what keeps other
  # runs off the port.
  defp bindable?(port) do
    listenable?(port, []) and listenable?(port, [:inet6, ipv6_v6only: true])
  end

  # The block whose first port takes a listener is this run's. Walks the blocks from one the
  # BEAM's OS pid picks, so runs mostly start apart. The listener is on loopback, like every
  # listener of the suite, and is never accepted on. A block is passed over too when something
  # that isn't a run of this suite listens on its second port, the proxy's: that port is never
  # probed again, and a listener on the IPv6 loopback there would get the browser's requests.
  defp claim_port_block do
    blocks = div(Range.size(@port_range), @port_block_size)
    start = :erlang.phash2(System.pid(), blocks)

    block =
      Enum.find_value(0..(blocks - 1), fn offset ->
        claim_port_block_at(@port_range.first + rem(start + offset, blocks) * @port_block_size)
      end)

    block || raise "every port block in #{inspect(@port_range)} is claimed"
  end

  defp claim_port_block_at(first) do
    case :gen_tcp.listen(first, ip: {127, 0, 0, 1}) do
      {:ok, socket} ->
        if bindable?(first + 1) do
          %{first: first, picks: 0, socket: socket}
        else
          :gen_tcp.close(socket)
          nil
        end

      {:error, :eaddrinuse} ->
        nil

      {:error, reason} ->
        raise "can't claim the port block at #{first}: #{inspect(reason)}"
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

  # Late forwards from earlier attempts must not linger, or a test's later
  # refute_receive could trip on them.
  defp flush_forwarded_messages do
    receive do
      {:forwarded, _node, _message} -> flush_forwarded_messages()
    after
      0 -> :ok
    end
  end

  defp forward_loop(forward_to) do
    receive do
      {:DOWN, _ref, :process, ^forward_to, _reason} ->
        :ok

      message ->
        send(forward_to, {:forwarded, node(), message})
        forward_loop(forward_to)
    end
  end

  # The picks come from a count of the run's own, never from the VM's unique integers, which
  # other code draws from too: in a block this small they would soon skip back onto a port
  # still waiting for its listener.
  defp free_port(attempt) when attempt > @port_block_size - 2 do
    raise "something listens on every port of this run's block"
  end

  defp free_port(attempt) do
    port =
      Agent.get_and_update(port_block(), fn %{first: first, picks: picks} = block ->
        {first + 2 + rem(picks, @port_block_size - 2), %{block | picks: picks + 1}}
      end)

    if bindable?(port) do
      port
    else
      free_port(attempt + 1)
    end
  end

  # No IPv6 on the machine means nothing listens there.
  defp listenable?(port, opts) do
    case :gen_tcp.listen(port, opts) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, :eaddrinuse} ->
        false

      {:error, reason} when reason in [:eaddrnotavail, :eafnosupport, :eprotonosupport] ->
        true

      {:error, reason} ->
        raise "can't probe port #{port}: #{inspect(reason)}"
    end
  end

  # Claimed on first use, so a peer or a proxy started from iex or `mix run` gets ports too.
  defp port_block do
    Process.whereis(@port_block_agent) || start_port_block()
  end

  # The port is given, so a restarted peer comes back on the one it had.
  defp start_peer_on_port(index, port, opts) do
    hologram_env = Keyword.get(opts, :hologram_env, "test")

    # Peer names form a bounded set (one per index a suite ever uses), so runtime atom
    # creation is safe here.
    # credo:disable-for-lines:3 Credo.Check.Warning.UnsafeToAtom
    {:ok, pid, node} =
      :peer.start_link(%{
        name: :"peer#{index}_#{System.pid()}",
        host: ~c"127.0.0.1",
        args: [~c"-setcookie", Atom.to_charlist(@cookie)],
        env: [
          {~c"HOLOGRAM_ENV", String.to_charlist(hologram_env)},
          {~c"HOLOGRAM_START", ~c"1"},
          # A production instance resolves its secret key base from the environment and nowhere
          # else - the dev/test fallback to the Phoenix endpoint's config does not apply - and
          # every initial page render needs it, to sign the replica identity it hands the page.
          # A peer booted with hologram_env: "prod" is such an instance, so it carries the var
          # exactly as a real deployment does.
          {~c"SECRET_KEY_BASE",
           ~c"test_secret_key_base_that_is_long_enough_for_testing_purposes_in_hologram"}
        ]
      })

    rpc(node, :code, :add_paths, [code_paths_without_mix()])
    copy_app_env(node, port)

    for {app, key, value} <- Keyword.get(opts, :app_env, []) do
      rpc(node, Application, :put_env, [app, key, value])
    end

    rpc(node, Application, :load, [@app])

    # The options ride along so a restart can reproduce the peer rather than a default one -
    # they are what makes it a production instance, or one pointed at another database.
    peer = %{index: index, node: node, opts: opts, pid: pid, port: port}

    # Registered before the app starts, so a peer whose boot fails is still stopped -
    # its node name has to be free for the next test either way.
    #
    # Peers die with the test process through the link, but asynchronously - and the next
    # test claims the same node names. Waiting here is what keeps that handover from
    # racing. Outside a test there is nothing to register the wait with, and nothing
    # queued behind this peer either, so a probe run from iex or `mix run` skips it.
    try do
      ExUnit.Callbacks.on_exit(fn -> stop_peer(peer) end)
    rescue
      ArgumentError -> :ok
    end

    if Keyword.get(opts, :boot_app, true) do
      {:ok, _apps} = boot_app(peer)
    end

    peer
  end

  # The agent holds the claim's socket, so it's started unlinked, to outlive the test or
  # the helper that first asked for a port. A claim that fails raises here as it did there.
  defp start_port_block do
    case Agent.start(&claim_port_block/0, name: @port_block_agent) do
      {:ok, pid} ->
        pid

      {:error, {:already_started, pid}} ->
        pid

      {:error, {exception, stacktrace}} when is_exception(exception) ->
        reraise exception, stacktrace
    end
  end
end
