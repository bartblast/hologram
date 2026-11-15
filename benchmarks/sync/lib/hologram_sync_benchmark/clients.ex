defmodule HologramSyncBenchmark.Clients do
  @moduledoc false

  # Many clients at once: started, prepared and connected with a bound on how many connect at a
  # time, then watched until each holds its whole pot.

  alias HologramSyncBenchmark.Client
  alias HologramSyncBenchmark.Peer

  # Descriptors the driver keeps for itself: the database connections, the peer's distribution
  # socket, the beams it loads.
  @reserved_descriptors 200

  @fill_poll_ms 100

  @doc """
  Raises when the machine can't hold the given number of clients, and warns when the given
  burst of connects can overflow the listen backlog.

  Driver and server node are separate OS processes and each holds one socket per client, so the
  per-process descriptor limit caps the client count. macOS caps every listen backlog at
  `kern.ipc.somaxconn`, so a burst of connects past it gets refused, which the clients retry.
  """
  @spec check_limits!(pos_integer, pos_integer) :: :ok
  def check_limits!(count, burst) do
    limit =
      ~c"ulimit -n"
      |> :os.cmd()
      |> List.to_string()
      |> String.trim()

    if limit != "unlimited" and String.to_integer(limit) - @reserved_descriptors < count do
      raise "#{count} clients need an open file limit above #{count + @reserved_descriptors}, " <>
              "it is #{limit}: raise it with `ulimit -n 65536`"
    end

    maybe_warn_backlog(burst)
  end

  @doc """
  Returns the options every client of a step greeting with the given page shares, with the
  server's model hash and protocol version read from the server node, since the driver never
  boots Hologram. Each client adds its own `:cookie_path`.
  """
  @spec base_opts(Peer.t(), String.t()) :: keyword
  def base_opts(peer, page) do
    [
      base_url: Peer.base_url(peer),
      model_hash: Peer.rpc(peer, Hologram.Entity.Model, :hash, []),
      page: page,
      protocol_version: Peer.rpc(peer, Hologram.Sync.Frame, :protocol_version, [])
    ]
  end

  @doc """
  Closes the given clients and returns :ok.
  """
  @spec close_all([pid]) :: :ok
  def close_all(clients) do
    Enum.each(clients, &Client.close/1)
  end

  @doc """
  Connects the given clients, at most `concurrency` at a time, and returns the failures as
  `{client, reason}` pairs.
  """
  @spec connect_all([pid], pos_integer) :: [{pid, term}]
  def connect_all(clients, concurrency) do
    run_all(clients, concurrency, &Client.connect/1)
  end

  @doc """
  Fetches the given clients' session cookies, at most `concurrency` at a time, and returns :ok,
  raising when any couldn't get one: preparing is the harness's part, untimed, so a failure there
  says the run can't measure anything rather than that the server is slow to sync.
  """
  @spec prepare_all!([pid], pos_integer) :: :ok
  def prepare_all!(clients, concurrency) do
    case run_all(clients, concurrency, &Client.prepare/1) do
      [] ->
        :ok

      [{_client, reason} | _more] = failures ->
        raise "#{length(failures)} of #{length(clients)} clients couldn't get a session " <>
                "cookie, the first because of #{inspect(reason)}"
    end
  end

  @doc """
  Starts one client per given option list, none of them connected, and returns them.

  Linked to the caller, so the clients go when the step that started them does.
  """
  @spec start_all([keyword]) :: [pid]
  def start_all(opts_list) do
    Enum.map(opts_list, fn opts ->
      {:ok, client} = Client.start_link(opts)
      client
    end)
  end

  @doc """
  Waits until every given client holds its whole pot or failed, or the timeout passes, and
  returns their reports in the clients' order.

  The timeout runs from this call, after every client connected, so it only bounds the wait. A
  client's own fill time is in its report, from its connect to its `synced` frame, and that's
  what a step's pass rule compares.
  """
  @spec await_fills([pid], non_neg_integer) :: [Client.report()]
  def await_fills(clients, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    await_fills_until(clients, deadline)
  end

  defp await_fills_until(clients, deadline) do
    reports = Enum.map(clients, &Client.report/1)
    settled? = Enum.all?(reports, &(&1.synced_all_at != nil or &1.failure != nil))

    if settled? or System.monotonic_time(:millisecond) >= deadline do
      reports
    else
      Process.sleep(@fill_poll_ms)
      await_fills_until(clients, deadline)
    end
  end

  defp maybe_warn_backlog(burst) do
    with {:unix, :darwin} <- :os.type(),
         {output, 0} <- System.cmd("sysctl", ["-n", "kern.ipc.somaxconn"]),
         somaxconn when somaxconn < burst <- parse_integer(output) do
      IO.warn(
        "kern.ipc.somaxconn is #{somaxconn}, below the #{burst} connects this step makes at " <>
          "once, so some get refused and retried: raise it with " <>
          "`sudo sysctl -w kern.ipc.somaxconn=4096`",
        []
      )
    end

    :ok
  end

  defp parse_integer(output) do
    output
    |> String.trim()
    |> String.to_integer()
  end

  defp run_all(clients, concurrency, fun) do
    clients
    |> Task.async_stream(fn client -> {client, fun.(client)} end,
      max_concurrency: concurrency,
      ordered: false,
      timeout: :infinity
    )
    |> Enum.flat_map(fn
      {:ok, {_client, :ok}} -> []
      {:ok, {client, {:error, reason}}} -> [{client, reason}]
    end)
  end
end
