defmodule HologramSyncBenchmark.Cases.Backlog do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Refactor.IoPuts

  # A long writing transaction holding up the dispatcher while many clients keep writing.
  #
  # The dispatcher reads the log up to the oldest transaction still open, so one left open stops
  # it, and everything committed meanwhile waits. For each batch it delivers, it also reads which
  # replicas have batches committed after that batch's transaction, and sends that list to every
  # session (`Hologram.DB.Oplog.replica_seqs_after/1`). Normally the list is empty. This case makes
  # it as long as it gets:
  #
  # 1. Transaction A writes one marked card and stays open.
  # 2. Transaction H takes a transaction id above A's and stays open.
  # 3. Writers commit batches for many replicas, all above H, so they pile up in the log.
  # 4. A commits. The log's edge moves up to H, so the dispatcher delivers A's batch alone, with the
  #    whole backlog above it. That's the read the case is after.
  # 5. H ends, and the whole backlog is delivered as one window.
  #
  # An open transaction holds the edge back for every database on the Postgres server, so this
  # needs a server of its own (see `check_server!/1`).

  alias Hologram.DB
  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Oplog
  alias Hologram.Mutation.Ref
  alias Hologram.Sync.Dispatcher
  alias HologramSyncBenchmark.Client
  alias HologramSyncBenchmark.Clients
  alias HologramSyncBenchmark.DB, as: BenchDB
  alias HologramSyncBenchmark.Entities.Card
  alias HologramSyncBenchmark.Measure
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Report
  alias HologramSyncBenchmark.Seeding
  alias HologramSyncBenchmark.Step
  alias HologramSyncBenchmark.Sweep
  alias HologramSyncBenchmark.Writer

  # Effects per batch a replica commits, each a card of its own.
  @batch_size 10

  @default_clients 100

  @default_sizes [30_000, 300_000]

  @direct_reads 5

  # How long a delivery may take before the step stops waiting and reports it as unfinished.
  @delivery_limit_ms 120_000

  @hold_wait_ms 30_000

  @ordinary_writes 3

  @page "HologramSyncBenchmark.BoardPage"

  # Cards kept out of the writers' way: the timed writes' markers must not be overwritten.
  @reserved_cards 10

  @writers 8

  @doc """
  Runs the case with the given options, writes its section into the README, and returns :ok.
  """
  @spec run(pid, keyword) :: :ok
  def run(conn, opts) do
    sizes = opts[:backlog_rows] || @default_sizes
    clients = Clients.single_count!(opts[:clients], @default_clients)
    memory_limit = opts[:memory_limit] * 1_073_741_824

    :ok = check_cards!(opts)
    :ok = check_server!(conn)
    :ok = Clients.check_limits!(clients, Step.connect_concurrency())
    :ok = Report.check_readme!()
    run_line = Report.run_line(conn)

    {_seeding, nil} = Seeding.board!(conn, Card, opts[:cards])

    {results, stopped} = measure_all(conn, sizes, clients, memory_limit, opts)

    # With nothing measured there's nothing to write, and writing would replace an earlier run's
    # good section with an empty one.
    if results == [] do
      raise "no backlog size was measured: #{inspect(stopped)}"
    end

    figure = figure(results, stopped, opts)
    IO.puts("Backlog: #{figure}")

    Report.write_case!(
      "backlog",
      "A long transaction holding up the dispatcher",
      run_line,
      options(clients, opts),
      figure,
      [{"Per backlog size", columns(), Enum.map(results, &row/1)}],
      figure_label: "Read of the batches above a delivered one"
    )
  end

  @doc """
  Writes one marked card and holds the transaction open until told to commit, telling the given
  process its transaction id. Runs on the server node, in a process of its own.
  """
  @spec hold_write(pid, module, term, String.t()) :: term
  def hold_write(owner, entity_type, id, value) do
    {:ok, {from, ref}} =
      DB.transaction(
        fn ->
          _written_at = Writer.update(entity_type, id, :title, value)
          {:ok, %{rows: [[xid]]}} = Connection.query("SELECT pg_current_xact_id()::text", [])

          send(owner, {:write_held, self(), String.to_integer(xid)})

          receive do
            {:commit, from, ref} -> {from, ref}
          end
        end,
        timeout: :infinity
      )

    send(from, {ref, :os.system_time(:microsecond)})
  end

  @doc """
  Commits batches of `@batch_size` effects for the given number of replicas, on the given cards,
  from several writers at once, until they've written at least the given number of effects, and
  returns :ok. Runs on the server node.
  """
  @spec write_backlog(tuple, pos_integer, pos_integer) :: :ok
  def write_backlog(ids, effects, replicas) do
    slice = div(tuple_size(ids) - @reserved_cards, @writers)
    batches = div(effects + @writers * @batch_size - 1, @writers * @batch_size)

    0..(@writers - 1)
    |> Task.async_stream(&write_batches(ids, &1, slice, batches, replicas),
      max_concurrency: @writers,
      timeout: :infinity
    )
    |> Stream.run()
  end

  @doc """
  Times the read of the replicas' batches above the given transaction, and returns the median in
  milliseconds with how many replicas it named and the size of what it returned. Runs on the
  server node.
  """
  @spec read_figures(non_neg_integer) :: map
  def read_figures(tx) do
    reads = for _read <- 1..@direct_reads, do: :timer.tc(Oplog, :replica_seqs_after, [tx])

    {_micros, seqs} = hd(reads)

    read_ms =
      reads
      |> Enum.map(fn {micros, _seqs} -> micros / 1_000 end)
      |> Measure.percentile(50)

    %{
      read_ms: read_ms,
      replicas: map_size(seqs),
      size_bytes: :erts_debug.flat_size(seqs) * :erlang.system_info(:wordsize)
    }
  end

  @doc """
  Returns the pid of the node's dispatcher. Runs on the server node.
  """
  @spec dispatcher :: pid
  def dispatcher do
    {Dispatcher, pid, _type, _modules} =
      Hologram.Sync.Supervisor
      |> Supervisor.which_children()
      |> List.keyfind(Dispatcher, 0)

    pid
  end

  # Each writer on cards of its own, in ascending order within a batch, so row locks can't
  # deadlock them.
  defp write_batches(ids, writer, slice, batches, replicas) do
    first_card = @reserved_cards + writer * slice

    for batch <- 0..(batches - 1) do
      offset = rem(batch * @batch_size, slice - @batch_size + 1)
      replica = rem(batch * @writers + writer, replicas)
      ref = %{replica_id: replica_id(replica), seq: batch + 1}
      positions = (first_card + offset)..(first_card + offset + @batch_size - 1)

      {:ok, _written} = Ref.with_ref(ref, fn -> write_batch(ids, positions, batch) end)
    end

    :ok
  end

  # As long as a real one, a UUID, since the list's size is one of the figures.
  defp replica_id(replica) do
    "00000000-0000-4000-8000-" <> String.pad_leading(Integer.to_string(replica), 12, "0")
  end

  defp write_batch(ids, positions, batch) do
    DB.transaction(fn ->
      Enum.each(positions, &Writer.update(Card, elem(ids, &1), :title, "b#{batch}"))
    end)
  end

  defp check_cards!(opts) do
    needed = @reserved_cards + @writers * @batch_size

    if opts[:cards] < needed do
      raise ArgumentError, "the backlog case needs at least #{needed} cards"
    end

    :ok
  end

  # An open transaction holds back every sync dispatcher on the Postgres server, whatever database
  # it reads, so a run sharing one would stall everything else using it.
  defp check_server!(conn) do
    %{rows: rows} =
      Postgrex.query!(
        conn,
        """
        SELECT DISTINCT datname FROM pg_stat_activity
        WHERE usesysid IS NOT NULL AND datname IS NOT NULL
          AND datname <> current_database() AND pid <> pg_backend_pid()
        """,
        []
      )

    if rows != [] do
      raise "the backlog case holds a transaction open, which stalls sync in every database on " <>
              "the server, and these have connections: #{Enum.map_join(rows, ", ", &hd/1)}. " <>
              "Run it on a server of its own, with BENCH_PG_PORT, see README.md"
    end

    :ok
  end

  # Numbered apart per size: the cards keep the markers an earlier size wrote, and a client filling
  # them would take one as this size's write arriving before it was made.
  defp measure_all(conn, sizes, clients, memory_limit, opts) do
    Sweep.over_sizes(
      sizes,
      &"Backlog: #{&1} log rows",
      &measure_size(conn, {&1, &2}, clients, memory_limit, opts),
      &summary/1
    )
  end

  # A failure at one size leaves the figures of the ones before it to be written.
  defp measure_size(conn, sized, clients, memory_limit, opts) do
    :ok = BenchDB.truncate_log!(conn)
    :ok = BenchDB.vacuum_analyze!(conn)

    Sweep.with_guarded_peer(memory_limit, &measure(&1, conn, sized, clients, opts))
  catch
    kind, reason -> {:failed, Report.short_reason(kind, reason)}
  end

  defp measure(peer, conn, {size, first_marker}, count, opts) do
    ids = Peer.rpc(peer, Writer, :ids, [Card])
    :ok = Peer.rpc(peer, Writer, :warm_up, [Card, elem(ids, @reserved_cards - 1), :title, "up"])

    clients =
      peer
      |> Clients.base_opts(@page)
      |> Keyword.put(:cookie_path, "/session")
      |> List.duplicate(count)
      |> Clients.start_all()

    try do
      :ok = Clients.fill!(clients, Step.connect_concurrency(), opts[:fill_timeout] * 1_000)

      ordinary_ms = ordinary_write_ms(peer, clients, ids, first_marker)
      held = hold(peer, conn, {ids, clients}, {size, first_marker}, opts)

      Map.merge(held, %{clients: count, ordinary_ms: ordinary_ms, size: size})
    after
      Clients.close_all(clients)
    end
  end

  # What a write costs to reach everyone with nothing held up, to set the held one against.
  defp ordinary_write_ms(peer, clients, ids, first_marker) do
    0..(@ordinary_writes - 1)
    |> Enum.map(fn offset ->
      number = first_marker + offset
      args = [Card, elem(ids, offset), :title, Client.marker(number)]
      committed_at = Peer.rpc(peer, Writer, :update, args)

      Clients.delivery_ms(clients, number, committed_at, @delivery_limit_ms)
    end)
    |> Enum.reject(&is_nil/1)
    |> Measure.percentile(50)
  end

  # The two markers set while the dispatcher is held up go past the ordinary writes', on cards of
  # their own.
  defp hold(peer, conn, {ids, clients}, {size, first_marker}, opts) do
    held_card = @ordinary_writes
    last_card = @ordinary_writes + 1
    held_number = first_marker + held_card
    last_number = first_marker + last_card
    dispatcher = Peer.rpc(peer, __MODULE__, :dispatcher, [])

    held_write = start_held_write(peer, elem(ids, held_card), Client.marker(held_number))
    blocker = start_blocker()

    try do
      :ok = Peer.rpc(peer, __MODULE__, :write_backlog, [ids, size, opts[:replicas]])

      args = [Card, elem(ids, last_card), :title, Client.marker(last_number)]
      _committed_at = Peer.rpc(peer, Writer, :update, args)

      # The planner's figures for the log are from when it was empty, and a long-lived log has
      # recent ones, so the read below runs with the plan a real one would.
      :ok = analyze_log(conn)

      log_rows = log_rows_above(conn, blocker.xid)
      direct = Peer.rpc(peer, __MODULE__, :read_figures, [held_write.xid])

      :ok = check_blocking!(conn, blocker)

      held_rise = Measure.start_memory_peak(peer)
      held_committed_at = commit_held_write(held_write)
      held_ms = Clients.delivery_ms(clients, held_number, held_committed_at, @delivery_limit_ms)
      held_rise_bytes = Measure.stop_memory_peak(held_rise)

      drain_rise = Measure.start_memory_peak(peer)
      released_at = release_blocker(blocker)

      drain_ms =
        released_at && Clients.delivery_ms(clients, last_number, released_at, @delivery_limit_ms)

      drain_rise_bytes = Measure.stop_memory_peak(drain_rise)

      :ok = Peer.sync_log(peer)

      %{
        direct: direct,
        dispatcher_restarted: Peer.rpc(peer, __MODULE__, :dispatcher, []) != dispatcher,
        drain_ms: drain_ms,
        drain_rise_bytes: drain_rise_bytes,
        heap_kills: Measure.heap_kills(peer.log_path),
        held_ms: held_ms,
        held_rise_bytes: held_rise_bytes,
        log_rows: log_rows,
        session_cuts: Measure.session_cuts(peer.log_path),
        streams_lost: Enum.count(clients, &Client.failed?/1)
      }
    after
      # Released whatever happened: left open, it would hold back every database on the server.
      release_blocker(blocker)
    end
  end

  # With the blocking transaction gone, the held write would be delivered with the whole backlog,
  # which has nothing above it, and the row would look fine. Asked of Postgres, since a backend
  # that ended leaves the process waiting on it none the wiser.
  defp check_blocking!(conn, blocker) do
    %{rows: [[status]]} =
      Postgrex.query!(conn, "SELECT pg_xact_status($1::text::xid8)", [
        Integer.to_string(blocker.xid)
      ])

    if status != "in progress" do
      raise "the blocking transaction ended before the held write committed: #{status}"
    end

    :ok
  end

  defp analyze_log(conn) do
    Postgrex.query!(conn, ~s|ANALYZE "#{Mapper.system_schema()}"."oplog"|, [], timeout: :infinity)

    :ok
  end

  defp log_rows_above(conn, xid) do
    %{rows: [[count]]} =
      Postgrex.query!(
        conn,
        ~s|SELECT count(*) FROM "#{Mapper.system_schema()}"."oplog" | <>
          ~s|WHERE "tx" > $1|,
        [xid],
        timeout: :infinity
      )

    count
  end

  defp start_held_write(peer, id, marker) do
    pid = Node.spawn(peer.node, __MODULE__, :hold_write, [self(), Card, id, marker])
    ref = Process.monitor(pid)

    receive do
      {:write_held, ^pid, xid} ->
        %{pid: pid, ref: ref, xid: xid}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        raise "the held write went down: #{inspect(reason)}"
    after
      @hold_wait_ms -> raise "the held write never started"
    end
  end

  defp commit_held_write(%{pid: pid, ref: monitor}) do
    ref = make_ref()
    send(pid, {:commit, self(), ref})

    receive do
      {^ref, committed_at} ->
        Process.demonitor(monitor, [:flush])
        committed_at

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        raise "the held write went down: #{inspect(reason)}"
    after
      @hold_wait_ms -> raise "the held write never committed"
    end
  end

  # On a connection of its own, since the driver's reads the counters meanwhile. Goes with the
  # caller, so a driver that dies can't leave the server's edge held back.
  defp start_blocker do
    owner = self()

    pid =
      spawn(fn ->
        owner_ref = Process.monitor(owner)

        {:ok, connection} =
          Config.connection_opts()
          |> Keyword.merge(backoff_type: :stop, sync_connect: true)
          |> Postgrex.start_link()

        Postgrex.transaction(connection, &hold_blocker(&1, owner, owner_ref), timeout: :infinity)
        send(owner, {:released, self(), :os.system_time(:microsecond)})
        GenServer.stop(connection)
      end)

    ref = Process.monitor(pid)

    receive do
      {:blocking, ^pid, xid} ->
        Process.demonitor(ref, [:flush])
        %{pid: pid, xid: xid}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        raise "the blocking transaction went down: #{inspect(reason)}"
    after
      @hold_wait_ms -> raise "the blocking transaction never started"
    end
  end

  defp hold_blocker(connection, owner, owner_ref) do
    %{rows: [[xid]]} = Postgrex.query!(connection, "SELECT pg_current_xact_id()::text", [])

    send(owner, {:blocking, self(), String.to_integer(xid)})

    receive do
      # A real writer's commit announces itself, which is what wakes the dispatcher. Without this,
      # the time to the whole backlog would hold a wait for the dispatcher's next poll, up to 5 s.
      :release -> Postgrex.query!(connection, "SELECT pg_notify($1, '')", [Oplog.channel()])
      {:DOWN, ^owner_ref, :process, _owner, _reason} -> :ok
    end
  end

  # Returns when the transaction ended, read right after its commit, or nil for one already gone.
  defp release_blocker(%{pid: pid}) do
    ref = Process.monitor(pid)
    send(pid, :release)

    receive do
      {:released, ^pid, released_at} ->
        Process.demonitor(ref, [:flush])
        released_at

      {:DOWN, ^ref, :process, ^pid, _reason} ->
        nil
    after
      @hold_wait_ms ->
        Process.demonitor(ref, [:flush])
        nil
    end
  end

  defp options(clients, opts) do
    [
      "#{opts[:cards]} cards read with a bare `allow :read`, #{clients} anonymous clients " <>
        "connected",
      "#{@writers} writers commit batches of #{@batch_size} effects for #{opts[:replicas]} " <>
        "replicas while one transaction holds the dispatcher up",
      "each size runs on a fresh log and a fresh server node, on a Postgres server of its own",
      "a delivery is waited on for at most #{div(@delivery_limit_ms, 1_000)} s, and a dash means " <>
        "it didn't reach every client in that time, or a client lost its stream first",
      "a run stops when the server node's memory passes #{opts[:memory_limit]} GB"
    ]
  end

  defp figure(results, stopped, opts) do
    last = List.last(results)

    text =
      "#{Report.cell(last.direct.read_ms)} ms with #{last.log_rows} log rows above it, naming " <>
        "#{last.direct.replicas} replicas, " <>
        "#{Report.cell(last.direct.size_bytes / 1_024)} KB copied to each session"

    case stopped do
      nil ->
        text

      %{reason: :memory, size: size} ->
        "#{text} (#{size} log rows stopped at the #{opts[:memory_limit]} GB memory limit)"

      %{reason: message, size: size} ->
        "#{text} (#{size} log rows failed: #{message})"
    end
  end

  defp summary(result) do
    "  #{result.log_rows} log rows above, direct read #{Report.cell(result.direct.read_ms)} ms, " <>
      "#{result.direct.replicas} replicas, #{Report.cell(result.direct.size_bytes / 1_024)} KB, " <>
      "ordinary write #{Report.cell(result.ordinary_ms)} ms, held write " <>
      "#{Report.cell(result.held_ms)} ms, drain #{Report.cell(result.drain_ms)} ms, " <>
      "#{result.streams_lost} streams lost, #{result.heap_kills} heap kills, " <>
      "#{result.session_cuts} sessions cut, dispatcher restarted: #{result.dispatcher_restarted}"
  end

  defp columns do
    [
      "Log rows above",
      "Replicas named",
      "Clients",
      "Read ms, direct",
      "List KB",
      "List MB across sessions",
      "Ordinary write ms",
      "Held-up write ms",
      "Memory rise MB",
      "Whole backlog ms",
      "Backlog memory rise MB",
      "Streams lost",
      "Heap kills",
      "Sessions cut",
      "Dispatcher restarted"
    ]
  end

  defp row(result) do
    [
      result.log_rows,
      result.direct.replicas,
      result.clients,
      result.direct.read_ms,
      result.direct.size_bytes / 1_024,
      result.direct.size_bytes * result.clients / 1_048_576,
      result.ordinary_ms,
      result.held_ms,
      result.held_rise_bytes / 1_048_576,
      result.drain_ms,
      result.drain_rise_bytes / 1_048_576,
      result.streams_lost,
      result.heap_kills,
      result.session_cuts,
      if(result.dispatcher_restarted, do: "yes", else: "no")
    ]
  end
end
