defmodule HologramSyncTests.Consistency.Run do
  @moduledoc false

  # One randomized run of a plan: the data written first, then the writers' transactions and the
  # clients' schedules all at once, then every client connected again and both checks. Answers
  # what each check found, with what the report needs to explain it.
  #
  # The run traps exits while it goes, so a client, writer or schedule that crashes is a failure in
  # the report, with the seed and the trace, rather than one that takes the test down without them.

  import HologramSyncTests.Helpers, only: [create!: 2, truncate_tables: 0]

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Oplog
  alias Hologram.Entity.Model, as: EntityModel
  alias Hologram.Sync.Catchup
  alias Hologram.Sync.Cursor
  alias Hologram.Sync.ReadEdge
  alias Hologram.Sync.Sessions
  alias HologramSyncTests.Consistency.Checks
  alias HologramSyncTests.Consistency.Client
  alias HologramSyncTests.Consistency.History
  alias HologramSyncTests.Consistency.Model
  alias HologramSyncTests.Consistency.Plan
  alias HologramSyncTests.Consistency.Writer
  alias HologramSyncTests.Entities.Tag

  # How long every client has to converge once the writes stop, how long the server has to read
  # the last commit off the log and its sessions to tell their clients, and how long the stores
  # must then stay as they are for a late frame moving one away to be seen.
  @converge_ms 20_000
  @read_ms 10_000
  @quiet_ms 500

  # How long a client has to close its stream when the run stops it.
  @stop_ms 5_000

  @typedoc """
  What a run found: the differences check 1 left in each client's store, the records check 2
  flagged, the clients' failures and the run's own, and the clients whose gap outgrew a replay
  and who weren't told to start over - with the history and each client's events and records for
  the report.
  """
  @type outcome :: %{
          clients: list(map),
          differences: list(map),
          failures: list(map),
          history: %{aborted: list(map), entries: list(map)},
          leaks: list(map),
          missed_resyncs: list(String.t())
        }

  @doc """
  Runs the given plan against the app served at the given base URL and answers what it found.
  Stops every client it started before it returns.
  """
  @spec run(Plan.t(), String.t()) :: outcome
  def run(plan, base_url) do
    trapping = Process.flag(:trap_exit, true)
    {:ok, history} = History.start_link()

    try do
      run_with(plan, base_url, history)
    after
      Agent.stop(history)
      Process.flag(:trap_exit, trapping)
    end
  end

  defp run_with(plan, base_url, history) do
    warm_up_log()
    truncate_tables()

    {:committed, _seed} = Writer.commit(history, :seed, writes(plan.seed_ops, [0]))

    clients = Enum.map(plan.clients, &start_client(&1, base_url))

    try do
      Enum.each(clients, &guarded(fn -> Client.connect(&1.pid) end))

      crashes = run_writers_and_schedules(plan, history, clients)

      Enum.each(clients, &guarded(fn -> Client.connect(&1.pid) end))

      outcome(clients, history, crashes)
    after
      Enum.each(clients, &stop_client/1)
    end
  end

  # The writers and the schedules run at once. A schedule waiting for the writers is told once
  # they've all returned. Answers what crashed, or what a schedule had to give up on.
  defp run_writers_and_schedules(plan, history, clients) do
    schedules =
      Enum.map(clients, fn client -> {client.name, Task.async(fn -> run_schedule(client) end)} end)

    writers =
      Enum.map(plan.writers, fn writer ->
        {writer.name, Task.async(fn -> run_writer(writer, history) end)}
      end)

    writer_crashes = await_tasks(writers)

    Enum.each(schedules, fn {_name, task} -> send(task.pid, :writers_done) end)

    writer_crashes ++ await_tasks(schedules)
  end

  defp await_tasks(named_tasks) do
    Enum.flat_map(named_tasks, fn {name, task} ->
      case Task.yield(task, :infinity) do
        {:ok, :ok} ->
          []

        {:ok, {:gave_up, step}} ->
          [%{client: name, failure: "gave up waiting at #{inspect(step)}"}]

        {:exit, reason} ->
          [%{client: name, failure: "crashed: #{inspect(reason)}"}]
      end
    end)
  end

  defp run_writer(writer, history) do
    Enum.each(writer.transactions, fn transaction ->
      Writer.commit(history, writer.name, writes(transaction.ops, transaction.holds))
    end)
  end

  defp writes(ops, holds) do
    ops
    |> Enum.zip(Stream.concat(holds, Stream.repeatedly(fn -> 0 end)))
    |> Enum.map(fn {op, hold_ms} ->
      {Plan.describe(op), fn -> Plan.apply_op(op) end, hold_ms}
    end)
  end

  defp run_schedule(client) do
    Enum.reduce_while(client.schedule, :ok, fn step, :ok ->
      case run_step(step, client.pid) do
        :ok -> {:cont, :ok}
        :timeout -> {:halt, {:gave_up, step}}
      end
    end)
  end

  defp run_step({:wait, ms}, _pid), do: Process.sleep(ms)

  defp run_step(:cut, pid), do: Client.cut(pid)

  defp run_step(:connect, pid), do: Client.connect(pid)

  defp run_step(:connect_cut_mid_fill, pid) do
    Client.connect(pid, cut_when: &match?([%{frame: "sync_deltas"} | _events], &1))
  end

  defp run_step(:await_synced, pid), do: await(fn -> Client.complete?(pid) end, @converge_ms)

  defp run_step(:await_writers, _pid) do
    receive do
      :writers_done -> :ok
    end
  end

  defp outcome(clients, history, crashes) do
    entries = History.entries(history)
    converged = Enum.map(clients, &guarded(fn -> converge(&1) end))

    read_failures =
      case await_log_read(entries) do
        :ok ->
          []

        :timeout ->
          [%{client: "the run", failure: "the server never read the last commit off the log"}]
      end

    Enum.each(Sessions.list(), fn {pid, _user_id} -> session_barrier(pid) end)
    Process.sleep(@quiet_ms)

    settled =
      clients
      |> Enum.zip(converged)
      |> Enum.map(fn
        {client, :dead} -> {:dead, client}
        {_client, converged_client} -> guarded(fn -> settle(converged_client, entries) end)
      end)

    {reports, dead} = split_dead(clients, settled)

    %{
      clients: reports ++ dead,
      differences:
        for(
          report <- reports,
          difference <- report.differences,
          do: %{client: report.name, difference: difference}
        ),
      failures:
        crashes ++
          read_failures ++
          Enum.map(
            dead,
            &%{client: &1.name, failure: dead_failure(&1.pid)}
          ) ++
          for(
            report <- reports,
            %{kind: :failure} = failure <- report.events,
            do: Map.put(failure, :client, report.name)
          ),
      history: %{aborted: History.aborted(history), entries: entries},
      leaks:
        for(report <- reports, leak <- report.leaks, do: Map.put(leak, :client, report.name)),
      missed_resyncs: for(report <- reports, missed_resync?(report), do: report.name)
    }
  end

  # A client that died has its calls exit here, which the run takes as the client having crashed.
  defp guarded(fun) do
    fun.()
  catch
    :exit, _reason -> :dead
  end

  defp split_dead(clients, settled) do
    clients
    |> Enum.zip(settled)
    |> Enum.reduce({[], []}, fn
      {client, :dead}, {reports, dead} -> {reports, [client | dead]}
      {client, {:dead, _client}}, {reports, dead} -> {reports, [client | dead]}
      {_client, report}, {reports, dead} -> {[report | reports], dead}
    end)
    |> then(fn {reports, dead} -> {Enum.reverse(reports), Enum.reverse(dead)} end)
  end

  # A client still alive stopped answering - stuck in a callback - and one that died says why.
  defp dead_failure(pid) do
    if Process.alive?(pid),
      do: "stopped answering calls",
      else: "crashed: #{inspect(crash_reason(pid))}"
  end

  # Why a linked client died, from the exit signal the run trapped.
  defp crash_reason(pid) do
    receive do
      {:EXIT, ^pid, reason} -> reason
    after
      0 -> :unknown
    end
  end

  defp converge(client) do
    case Checks.await_converged(client.pid, client.user_id, @converge_ms) do
      :ok -> {client, []}
      {:error, differences} -> {client, differences}
    end
  end

  # Once the server has read every commit off the log and the quiet period passed, a store that
  # converged has to still hold the same, still complete, and the records are all in. A store that
  # never converged has its differences told once, as the first poll left them.
  defp settle({client, first_differences}, entries) do
    expected = Model.expected(Model.snapshot(), client.user_id)

    {complete?, store} = Client.view(client.pid)
    settled = Checks.diff(store, expected)
    incomplete = if complete?, do: [], else: [:incomplete]
    records = Client.records(client.pid)

    differences =
      if first_differences == [],
        do: Enum.map(incomplete ++ settled, &{:after_quiet, &1}),
        else: first_differences

    %{
      client
      | differences: differences,
        events: Client.events(client.pid),
        leaks: Checks.leaks(records, entries, client.user_id),
        records: records
    }
  end

  # The server has routed every commit once the dispatcher's read edge is past the last one's
  # transaction id: everything below the edge had ended when it was read.
  defp await_log_read([]), do: :ok

  defp await_log_read(entries) do
    last_xid =
      entries
      |> Enum.map(& &1.xid)
      |> Enum.max()

    await(fn -> (ReadEdge.get(ReadEdge) || 0) > last_xid end, @read_ms)
  end

  # Every batch routed is in a session's mailbox once the read edge passes the last commit. A
  # system message is handled after the callback running and every message ahead of it, so once a
  # session answers one it has told its client all it was given. A session gone, or one still
  # waiting on its client past the timeout, is left to the quiet period - its late frames carry the
  # final state, so they can only show a problem, never cause one.
  defp session_barrier(pid) do
    :sys.get_state(pid, @read_ms)
  catch
    :exit, _reason -> :ok
  end

  # A client away until the writers were done has to have been told to start over when its gap
  # outgrew a replay - counted from the place it came back with, in the log as it stands.
  defp missed_resync?(report) do
    :await_writers in report.schedule and gap_too_large?(report) and
      "gap_too_large" not in resync_reasons(report)
  end

  defp gap_too_large?(report) do
    with %{cursor: cursor} when is_binary(cursor) <- last_connect(report),
         {:ok, tx, seq, _policy_hash, _types_hash} <- Cursor.decode(cursor) do
      limit = Catchup.gap_limit()
      {count, _other_model?} = Oplog.count_after(tx, seq, limit + 1, EntityModel.hash())

      count > limit
    else
      _no_place -> false
    end
  end

  defp last_connect(report) do
    report.events
    |> Enum.filter(&(&1.kind == :connect))
    |> List.last()
  end

  defp resync_reasons(report) do
    for %{frame: "sync_resync", reason: reason} <- report.events, do: reason
  end

  # A session's first place is the oldest transaction still running when it starts, which a
  # transaction anywhere on the database server can hold back. Below the log's oldest change, a
  # returning client's place reads as one from before the log, and it's sent everything again for
  # retention - on a fresh log, every client coming back from its first place would be, and no
  # catch-up would run. So the log gets a change first, and the run starts once nothing older than
  # it still runs. The row goes with the truncate after; the change stays in the log.
  defp warm_up_log do
    {:ok, xid} =
      DB.transaction(fn ->
        create!(Tag, name: "warm-up")
        {:ok, %{rows: [[xid]]}} = Connection.query("SELECT pg_current_xact_id()::text", [])

        String.to_integer(xid)
      end)

    if await(fn -> Oplog.current_xmin() > xid end, @read_ms) == :timeout do
      raise "a transaction elsewhere on the database server kept running for #{@read_ms} ms, " <>
              "so a returning client's place would read as one from before the log"
    end
  end

  defp start_client(planned, base_url) do
    {:ok, pid} = Client.start_link(base_url: base_url, user_id: planned.user_id)

    Map.merge(planned, %{differences: [], events: [], leaks: [], pid: pid, records: []})
  end

  # Every client is stopped, whatever the others do: one that died meanwhile, or one stuck in a
  # callback - a connect whose request the server never answers - is killed rather than waited on.
  defp stop_client(client) do
    Client.stop(client.pid, @stop_ms)
  catch
    :exit, _reason ->
      # Unlinked first, so its exit signal can't reach this process once it no longer traps exits.
      Process.unlink(client.pid)
      Process.exit(client.pid, :kill)
  end

  defp await(condition, timeout_ms) do
    await_until(condition, System.monotonic_time(:millisecond) + timeout_ms)
  end

  defp await_until(condition, deadline) do
    cond do
      condition.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        :timeout

      true ->
        Process.sleep(20)
        await_until(condition, deadline)
    end
  end
end
