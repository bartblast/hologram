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

  @marker_poll_ms 20

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
  Waits until every given client that came back holds its whole pot again or failed, or the timeout
  passes, and returns their reports in the clients' order.
  """
  @spec await_caught_up([pid], non_neg_integer) :: [Client.report()]
  def await_caught_up(clients, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    await_reports(clients, deadline, &(&1.caught_up_at != nil or &1.failure != nil))
  end

  @doc """
  Returns the one client count a case running at a single count was given, or the given default,
  raising on several rather than quietly taking one of them.
  """
  @spec single_count!([pos_integer] | nil, pos_integer) :: pos_integer
  def single_count!(nil, default), do: default

  def single_count!([count], _default), do: count

  def single_count!(counts, _default) do
    raise ArgumentError, "this case runs at one client count, got: #{inspect(counts)}"
  end

  @doc """
  Closes the given clients and returns :ok.
  """
  @spec close_all([pid]) :: :ok
  def close_all(clients) do
    Enum.each(clients, &Client.close/1)
  end

  @doc """
  Has each given client come back at its own uniformly random moment within the given
  milliseconds, the way browsers retrying with jitter spread over a moment, and returns :ok.
  """
  @spec come_back_all([pid], non_neg_integer) :: :ok
  def come_back_all(clients, spread_ms) do
    Enum.each(clients, fn client ->
      :ok = Client.come_back(client, :rand.uniform(spread_ms + 1) - 1)
    end)
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
  Closes the stream of each given client, keeping what it knows, and returns the ones that
  couldn't leave as `{client, reason}` pairs.
  """
  @spec leave_all([pid]) :: [{pid, term}]
  def leave_all(clients) do
    Enum.flat_map(clients, fn client ->
      case Client.leave(client) do
        :ok -> []
        {:error, reason} -> [{client, reason}]
      end
    end)
  end

  @doc """
  Waits for the marker with the given number to reach every given client, and returns the
  milliseconds from the given commit to the last arrival, or nil when one never got it: past the
  given limit, or for having lost its stream, since it doesn't come back. Waits on the others past
  a client that failed, so what's read next covers them too.
  """
  @spec delivery_ms([pid], non_neg_integer, integer, pos_integer) :: float | nil
  def delivery_ms(clients, number, committed_at, limit_ms) do
    deadline = System.monotonic_time(:millisecond) + limit_ms

    if await_marker(clients, number, deadline) do
      last_at =
        clients
        |> Enum.map(&Map.fetch!(Client.report(&1).markers, number))
        |> Enum.max()

      (last_at - committed_at) / 1_000
    end
  end

  defp await_marker(clients, number, deadline) do
    waiting = Enum.reject(clients, &Client.has_marker?(&1, number))

    cond do
      waiting == [] ->
        true

      Enum.all?(waiting, &Client.failed?/1) or System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(@marker_poll_ms)
        await_marker(waiting, number, deadline)
    end
  end

  @doc """
  Connects the given clients a group at a time, each group once the one before it is filled, and
  returns the failures to connect and the reports in the clients' order. The given time covers all
  of them, and a group whose turn comes after it isn't connected.

  For a case whose fills aren't what it measures. A connect returns as soon as the stream's headers
  are in, so connecting a limited number at a time doesn't limit how many fill at once, and each
  holds its rows in memory while it sends them.
  """
  @spec fill_in_groups([pid], pos_integer, non_neg_integer) :: {[{pid, term}], [Client.report()]}
  def fill_in_groups(clients, group_size, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    {failures, reports} =
      clients
      |> Enum.chunk_every(group_size)
      |> Enum.map_reduce([], fn group, reports ->
        remaining_ms = max(deadline - System.monotonic_time(:millisecond), 0)

        # Past the deadline a group isn't connected at all: with no wait left to hold each back,
        # the rest would all fill at once.
        group_failures = if remaining_ms > 0, do: connect_all(group, group_size), else: []
        remaining_ms = max(deadline - System.monotonic_time(:millisecond), 0)

        {group_failures, [await_fills(group, remaining_ms) | reports]}
      end)

    {List.flatten(failures),
     reports
     |> Enum.reverse()
     |> Enum.concat()}
  end

  @doc """
  Prepares and connects the given clients, at most `concurrency` at a time, waits for their fills
  and returns :ok, raising when one couldn't connect or fill within the given time.
  """
  @spec fill!([pid], pos_integer, non_neg_integer) :: :ok
  def fill!(clients, concurrency, timeout_ms) do
    prepare_all!(clients, concurrency)

    case connect_all(clients, concurrency) do
      [] -> :ok
      [{_client, reason} | _more] -> raise "a client couldn't connect: #{inspect(reason)}"
    end

    reports = await_fills(clients, timeout_ms)

    case Enum.find(reports, &(&1.synced_all_at == nil or &1.failure != nil)) do
      nil -> :ok
      report -> raise "a client never filled: #{inspect(report.failure)}"
    end
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

    await_reports(clients, deadline, &(&1.synced_all_at != nil or &1.failure != nil))
  end

  defp await_reports(clients, deadline, settled?) do
    reports = Enum.map(clients, &Client.report/1)

    if Enum.all?(reports, settled?) or System.monotonic_time(:millisecond) >= deadline do
      reports
    else
      Process.sleep(@fill_poll_ms)
      await_reports(clients, deadline, settled?)
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
