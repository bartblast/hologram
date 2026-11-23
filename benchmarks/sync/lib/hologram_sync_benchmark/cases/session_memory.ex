defmodule HologramSyncBenchmark.Cases.SessionMemory do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Refactor.IoPuts

  # What one connected client's sync session costs a node while it sits idle, for clients holding
  # 1,000, 10,000 and 100,000 rows. A session keeps the ids of what its client holds, so this is
  # what a node pays for a connected tab's session, on top of its stream and socket, and what
  # decides whether keeping one shared list for rows everyone may read (#1676) is worth it.
  #
  # Each row count is seeded on its own. Each client connects once the one before it is filled, so
  # their fills don't add up on the node, and each session is read once all are. Then they leave
  # and come back, and the returning sessions are read too, since those build what they hold
  # another way.

  alias Hologram.DB.QueryCache
  alias Hologram.Sync.Fill
  alias Hologram.Sync.Pool
  alias Hologram.Sync.Sessions
  alias HologramSyncBenchmark.Clients
  alias HologramSyncBenchmark.Entities.Card
  alias HologramSyncBenchmark.Measure
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Report
  alias HologramSyncBenchmark.Seeding
  alias HologramSyncBenchmark.Sweep
  alias HologramSyncBenchmark.Writer

  @clients 10

  # Fewer clients past this many rows, since a fill reads all of a type's rows at once.
  @clients_many_rows 3

  @many_rows 100_000

  @page "HologramSyncBenchmark.BoardPage"

  @id_reads 3

  @poll_ms 50

  @rows [1_000, 10_000, 100_000]

  # How long a closed client's session may take to end, and a new one to settle after its
  # catch-up, before it's read.
  @sessions_gone_ms 30_000

  @settle_ms 500

  @doc """
  Runs the session memory case with the given options, writes its section into the README, and
  returns :ok.
  """
  @spec run(pid, keyword) :: :ok
  def run(conn, opts) do
    row_counts = opts[:rows] || @rows
    memory_limit = opts[:memory_limit] * 1_073_741_824

    :ok =
      row_counts
      |> Enum.map(&client_count/1)
      |> Enum.max()
      |> Clients.check_limits!(1)

    :ok = Report.check_readme!()
    run_line = Report.run_line(conn)

    {results, stopped} = measure_all(conn, row_counts, memory_limit, opts)

    # With nothing measured there's nothing to write, and writing would replace an earlier run's
    # good section with an empty one.
    if results == [] do
      raise "no row count was measured: #{inspect(stopped)}"
    end

    figure = figure(results, stopped, opts)

    IO.puts("Memory per session: #{figure}")

    Report.write_case!(
      "session_memory",
      "Memory per connected session",
      run_line,
      options(opts),
      figure,
      [{"Per session, median", columns(), Enum.map(results, &row/1)}],
      figure_label: "Memory per session"
    )
  end

  @doc """
  Times what a returning anonymous client's session reads to know what its client holds, the ids
  of every synced type, through sync's pool as a session reads them, and returns the median of
  three, in milliseconds. Runs on the server node.
  """
  @spec read_ids_ms :: float
  def read_ids_ms do
    synced_types = QueryCache.synced_types()

    1..@id_reads
    |> Enum.map(fn _read ->
      {micros, :ok} = :timer.tc(fn -> Pool.run(fn -> read_all_ids(synced_types) end) end)

      micros / 1_000
    end)
    |> Measure.percentile(50)
  end

  defp read_all_ids(synced_types) do
    Enum.each(synced_types, &Fill.read_ids(&1, nil))
  end

  @doc """
  Returns what the given sync session and the stream serving it hold, in bytes, read as they stand
  and again after collecting the session's garbage. The stream is never collected: its process is
  killed past a heap size. Runs on the server node.
  """
  @spec read_session(pid) :: map
  def read_session(session) do
    stream = :sys.get_state(session).outbox.client
    {memory, binaries} = Measure.process_bytes(session)
    {stream_memory, stream_binaries} = Measure.process_bytes(stream)

    :erlang.garbage_collect(session)
    {collected_memory, collected_binaries} = Measure.process_bytes(session)

    %{
      collected: collected_memory + collected_binaries,
      collected_binaries: collected_binaries,
      standing: memory + binaries,
      stream: stream_memory + stream_binaries
    }
  end

  defp client_count(rows) when rows >= @many_rows, do: @clients_many_rows

  defp client_count(_rows), do: @clients

  defp measure_all(conn, row_counts, memory_limit, opts) do
    {results, stopped} =
      Enum.reduce_while(row_counts, {[], nil}, fn rows, {results, nil} ->
        IO.puts("Rows: #{rows}")

        case measure_rows(conn, rows, memory_limit, opts) do
          {:ok, result} ->
            IO.puts(summary(result))
            {:cont, {[result | results], nil}}

          {:stopped, memory} ->
            IO.puts("  STOPPED at the memory limit")
            {:halt, {results, %{reason: :memory, memory: memory, rows: rows}}}

          {:failed, message} ->
            IO.puts("  FAILED: #{message}")
            {:halt, {results, %{reason: message, rows: rows}}}
        end
      end)

    {Enum.reverse(results), stopped}
  end

  # A failure at one row count leaves the figures of the ones before it to be written.
  defp measure_rows(conn, rows, memory_limit, opts) do
    {_seeding, nil} = Seeding.board!(conn, Card, rows)

    Sweep.with_guarded_peer(memory_limit, &measure(&1, rows, opts))
  catch
    kind, reason -> {:failed, Report.short_reason(kind, reason)}
  end

  defp measure(peer, rows, opts) do
    ids = Peer.rpc(peer, Writer, :ids, [Card])
    :ok = Peer.rpc(peer, Writer, :warm_up, [Card, elem(ids, 0), :title, "warm-up"])

    base =
      peer
      |> Clients.base_opts(@page)
      |> Keyword.put(:cookie_path, "/session")

    clients =
      base
      |> List.duplicate(client_count(rows))
      |> Clients.start_all()

    try do
      Clients.prepare_all!(clients, 1)

      first = read_filled(peer, clients, opts)
      returning = read_returning(peer, clients, opts)

      %{clients: length(clients), first: first, returning: returning, rows: rows}
    after
      Clients.close_all(clients)
    end
  end

  defp read_filled(peer, clients, opts) do
    # A connect returns as soon as the stream's headers are in, before the fill, so each client
    # waits for the one before it to hold everything.
    Enum.each(clients, fn client ->
      case Clients.connect_all([client], 1) do
        [] -> :ok
        [{_client, reason}] -> raise "a client couldn't connect: #{inspect(reason)}"
      end

      [report] = Clients.await_fills([client], opts[:fill_timeout] * 1_000)

      if report.synced_all_at == nil or report.failure != nil do
        raise "a client never filled within #{opts[:fill_timeout]} s, failure: " <>
                inspect(report.failure)
      end
    end)

    read_sessions(peer, length(clients))
  end

  # Waits for the sessions of the clients that left to end, so the ones read are the returning
  # ones. They were told nothing changed, so what they hold comes from reading their ids.
  defp read_returning(peer, clients, opts) do
    case Clients.leave_all(clients) do
      [] -> :ok
      [{_client, reason} | _more] -> raise "a client couldn't leave: #{inspect(reason)}"
    end

    :ok = await_sessions_gone(peer, now_ms() + @sessions_gone_ms)

    # One at a time, so the time is the session reading its ids rather than queueing at the gate.
    catchup_ms =
      clients
      |> Enum.map(&come_back_alone(&1, opts))
      |> Measure.percentile(50)

    peer
    |> read_sessions(length(clients))
    |> Map.merge(%{
      catchup_ms: catchup_ms,
      read_ids_ms: Peer.rpc(peer, __MODULE__, :read_ids_ms, [])
    })
  end

  defp come_back_alone(client, opts) do
    :ok = Clients.come_back_all([client], 0)

    [report] = Clients.await_caught_up([client], opts[:fill_timeout] * 1_000)

    if report.caught_up_at == nil or report.failure != nil do
      raise "a client never caught up within #{opts[:fill_timeout]} s, failure: " <>
              inspect(report.failure)
    end

    (report.caught_up_at - report.returned_at) / 1_000
  end

  defp await_sessions_gone(peer, deadline) do
    cond do
      Peer.rpc(peer, Sessions, :list, []) == [] ->
        :ok

      now_ms() >= deadline ->
        raise "the sessions of the clients that left were still there after " <>
                "#{@sessions_gone_ms} ms"

      true ->
        Process.sleep(@poll_ms)
        await_sessions_gone(peer, deadline)
    end
  end

  # Read after a moment, so each session has finished what it was doing when its last frame went
  # out and settled the way one sitting idle does.
  defp read_sessions(peer, count) do
    Process.sleep(@settle_ms)

    sessions = Peer.rpc(peer, Sessions, :list, [])

    if length(sessions) != count do
      raise "expected #{count} sync sessions on the node, found #{length(sessions)}"
    end

    read =
      Enum.map(sessions, fn {pid, _user} -> Peer.rpc(peer, __MODULE__, :read_session, [pid]) end)

    Map.new([:collected, :collected_binaries, :standing, :stream], fn key ->
      {key,
       read
       |> Enum.map(&Map.fetch!(&1, key))
       |> Measure.percentile(50)}
    end)
  end

  defp options(opts) do
    [
      "cards read with a bare `allow :read`, so every client holds every card, " <>
        "#{Enum.join(opts[:rows] || @rows, ", ")} of them, each seeded on its own",
      "#{@clients} anonymous clients, #{@clients_many_rows} from #{@many_rows} rows up, " <>
        "each connecting once the one before it is filled, sitting idle when read",
      "a build with no permission checks in the browser, so rows carry no verdicts. With them, a " <>
        "first arrival also keeps a verdict entry per row, and a returning session doesn't",
      "a run stops when the server node's memory passes #{opts[:memory_limit]} GB"
    ]
  end

  defp figure(results, stopped, opts) do
    text =
      case List.last(results) do
        nil ->
          "none measured"

        last ->
          "#{kb(last.first.standing)} KB as it sits idle, #{kb(last.first.collected)} KB after " <>
            "collection, for #{last.rows} rows, " <>
            "#{Report.cell(last.first.collected_binaries / last.rows)} off-heap binary bytes " <>
            "per row"
      end

    case stopped do
      nil ->
        text

      %{reason: :memory, rows: rows} ->
        "#{text} (#{rows} rows stopped at the #{opts[:memory_limit]} GB memory limit)"

      %{reason: message, rows: rows} ->
        "#{text} (#{rows} rows failed: #{message})"
    end
  end

  defp summary(result) do
    "  #{result.clients} clients, first arrival #{kb(result.first.standing)} KB, " <>
      "#{kb(result.first.collected)} KB collected, returning #{kb(result.returning.standing)} " <>
      "KB, #{kb(result.returning.collected)} KB collected, " <>
      "#{Report.cell(result.first.collected_binaries / result.rows)} off-heap binary bytes " <>
      "per row, " <>
      "stream #{kb(result.first.stream)} KB"
  end

  defp columns do
    [
      "Rows",
      "Clients",
      "First arrival KB",
      "After collection KB",
      "Of which off-heap binaries KB",
      "Rest KB",
      "Off-heap binary bytes per row",
      "Returning KB",
      "Returning after collection KB",
      "Returning off-heap binary bytes per row",
      "Returning, back to caught up ms",
      "Reading its ids ms",
      "Stream KB"
    ]
  end

  defp row(result) do
    %{first: first, returning: returning, rows: rows} = result

    [
      rows,
      result.clients,
      first.standing / 1_024,
      first.collected / 1_024,
      first.collected_binaries / 1_024,
      (first.collected - first.collected_binaries) / 1_024,
      first.collected_binaries / rows,
      returning.standing / 1_024,
      returning.collected / 1_024,
      returning.collected_binaries / rows,
      returning.catchup_ms,
      returning.read_ids_ms,
      first.stream / 1_024
    ]
  end

  defp kb(bytes), do: Report.cell(bytes / 1_024)

  defp now_ms, do: System.monotonic_time(:millisecond)
end
