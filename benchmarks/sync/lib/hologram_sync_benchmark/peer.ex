defmodule HologramSyncBenchmark.Peer do
  @moduledoc false

  # The server node: the one node that syncs, and the one every figure about "the node" is read
  # from. Started by the driver as a :peer, so what the clients cost the driver never counts
  # against it.
  #
  # Started the way the cluster test app starts its peers (test/cluster/test/support/cluster.ex):
  #
  # - HOLOGRAM_ENV=test and HOLOGRAM_START=1. Without HOLOGRAM_START Hologram starts no children
  #   in :dev or :test. As :dev it would also start live reload, which needs Mix, and the peer
  #   has none. As :test it starts the pool alone, so the schema is converged here after boot,
  #   which is what Hologram.Test.setup/0 does.
  # - the driver's code path minus Mix's ebin, since with Mix loadable but not started
  #   Hologram's app resolution dies on Mix.ProjectStack.
  # - application env copied from the driver, the endpoint flipped to serve.

  alias Hologram.DB
  alias Hologram.DB.Config
  alias Hologram.DB.Mapper
  alias Hologram.DB.SchemaReconciler

  @app :hologram_sync_benchmark

  @cookie :hologram_sync_benchmark

  @copied_env_apps [:hologram, :logger, :phoenix, :phoenix_pubsub, @app]

  @endpoint HologramSyncBenchmarkWeb.Endpoint

  # Where the server node logs, relative to this app's folder, new for each peer. Its console
  # output would otherwise be relayed to the driver's terminal, where a step that kills thousands
  # of streams would bury the report.
  @log_path "tmp/server.log"

  @log_handler :bench_file

  @type t :: %{log_path: String.t(), node: node, pid: pid, port: pos_integer}

  @doc """
  Returns the base URL clients reach the given peer at.
  """
  @spec base_url(t) :: String.t()
  def base_url(peer), do: "http://127.0.0.1:#{peer.port}"

  @doc """
  Converges the database schema to the app's model and returns :ok. Runs on the peer.
  """
  @spec converge_schema :: :ok
  def converge_schema do
    _result = SchemaReconciler.reconcile(DB.reconciliation_context())

    :ok
  end

  @doc """
  Creates the benchmark's database when the server has none yet, and returns :ok.

  Nothing else creates it: Hologram's own bootstrap does, but only in a test run, and it drops
  the schema first. Nothing is dropped here, the schema is converged from the model when the
  peer boots.
  """
  @spec ensure_database! :: :ok
  def ensure_database! do
    database = Keyword.fetch!(Config.connection_opts(), :database)

    # Never retried, so a server that is down fails at the first query below, with the reason
    # logged above it, rather than after the pool's backoff.
    {:ok, conn} =
      [database: "postgres"]
      |> Config.connection_opts()
      |> Keyword.merge(backoff_type: :stop, sync_connect: true)
      |> Postgrex.start_link()

    %{rows: rows} =
      Postgrex.query!(conn, "SELECT 1 FROM pg_database WHERE datname = $1", [database])

    if rows == [] do
      # CREATE DATABASE takes no parameters, so the name goes in as a quoted identifier.
      Postgrex.query!(conn, "CREATE DATABASE #{Mapper.quote_identifier(database)}", [])
    end

    GenServer.stop(conn)
  end

  @doc """
  Calls the given function on the given peer and returns its result, raising when the call
  fails there.
  """
  @spec rpc(t, module, atom, list, timeout) :: term
  def rpc(peer, module, fun, args, timeout \\ :infinity) do
    :erpc.call(peer.node, module, fun, args, timeout)
  end

  @doc """
  Starts the driver's distribution, so it can start peers, and returns :ok.
  """
  @spec start_distribution! :: :ok
  def start_distribution! do
    {_output, 0} = System.cmd("epmd", ["-daemon"])

    case Node.start(:"bench@127.0.0.1", name_domain: :longnames) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    Node.set_cookie(@cookie)

    :ok
  end

  @doc """
  Starts the server node with the app booted and its schema converged, and returns it.

  Not linked to the caller, so a server node that dies mid-step doesn't take the driver with it,
  and the step can still report what it measured. A step stops its peer whether it returns or
  fails (see `with_peer/1`), since an unlinked peer outlives a caller that raises. The node dies
  with the driver's VM: a peer halts when it loses the connection to the node that started it.
  """
  @spec start! :: t
  def start! do
    port = Keyword.fetch!(Application.fetch_env!(@app, @endpoint)[:http], :port)

    {:ok, pid, node} =
      :peer.start(%{
        name: :bench_server,
        host: ~c"127.0.0.1",
        args: [~c"-setcookie", Atom.to_charlist(@cookie)],
        env: [{~c"HOLOGRAM_ENV", ~c"test"}, {~c"HOLOGRAM_START", ~c"1"}]
      })

    peer = %{log_path: Path.expand(@log_path), node: node, pid: pid, port: port}

    # Stopped here when the boot fails, since the caller never gets the peer to stop. Caught
    # rather than rescued: a call that exits on the peer comes back as an exit.
    try do
      boot(peer)
    catch
      kind, reason ->
        stop_after_failure(peer)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end

    peer
  end

  @doc """
  Flushes the given peer's log file and returns :ok.

  The file handler buffers its writes, so lines logged in the last seconds are only in the file
  after this. A peer that is gone has nothing left to flush.
  """
  #
  # Whatever the flush answers counts as done, since a log that can't be flushed is no reason to
  # keep the peer up. The call's timeout is longer than the handler's own 5 s, so a busy handler
  # answers rather than the call timing out.
  @spec sync_log(t) :: :ok
  def sync_log(peer) do
    _result = rpc(peer, :logger_std_h, :filesync, [@log_handler], 8_000)

    :ok
  catch
    _kind, _reason -> :ok
  end

  @doc """
  Starts a server node, calls the given function with it and returns the function's result,
  stopping the node whatever the function does.
  """
  @spec with_peer((t -> result)) :: result when result: term
  def with_peer(fun) do
    peer = start!()

    result =
      try do
        fun.(peer)
      catch
        kind, reason ->
          stop_after_failure(peer)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end

    :ok = stop(peer)

    result
  end

  @doc """
  Stops the given peer, its log flushed first, and returns once its node has left, so the next
  one can take its name and port.
  """
  @spec stop(t) :: :ok
  def stop(peer) do
    :ok = sync_log(peer)

    # A peer that is already gone is not an error: what matters is that its node has left.
    try do
      :peer.stop(peer.pid)
    catch
      :exit, _reason -> :ok
    end

    await_node_down(peer.node, 500)
  end

  # Before the app boots, so the boot's own warnings are in it too. Written over at each start,
  # so the log holds one peer's life, which is one sweep step.
  defp add_log_file(peer) do
    peer.log_path
    |> Path.dirname()
    |> File.mkdir_p!()

    config = %{config: %{file: String.to_charlist(peer.log_path), modes: [:write]}}

    :ok = rpc(peer, :logger, :add_handler, [@log_handler, :logger_std_h, config])
  end

  # A peer that won't stop after something else failed mustn't hide what failed.
  defp stop_after_failure(peer) do
    stop(peer)
  catch
    _kind, _reason -> :ok
  end

  defp boot(peer) do
    :ok = rpc(peer, :code, :add_paths, [code_paths_without_mix()])
    copy_app_env(peer)
    add_log_file(peer)

    {:ok, _apps} = rpc(peer, Application, :ensure_all_started, [@app])
    :ok = rpc(peer, __MODULE__, :converge_schema, [])

    # Removed once booted rather than before: the Logger application sets the console handler up
    # as it starts.
    :ok = rpc(peer, :logger, :remove_handler, [:default])
  end

  defp await_node_down(node, 0), do: raise("#{inspect(node)} did not stop")

  defp await_node_down(node, attempts_left) do
    if node in Node.list(:connected) do
      Process.sleep(10)
      await_node_down(node, attempts_left - 1)
    else
      :ok
    end
  end

  defp code_paths_without_mix do
    Enum.reject(:code.get_path(), fn path ->
      path
      |> List.to_string()
      |> String.ends_with?("/mix/ebin")
    end)
  end

  defp copy_app_env(peer) do
    for app <- @copied_env_apps, {key, value} <- Application.get_all_env(app) do
      :ok = rpc(peer, Application, :put_env, [app, key, value])
    end

    endpoint_config =
      @app
      |> Application.fetch_env!(@endpoint)
      |> Keyword.put(:server, true)

    :ok = rpc(peer, Application, :put_env, [@app, @endpoint, endpoint_config])
  end
end
