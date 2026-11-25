defmodule HologramSyncTests.Consistency.Run do
  @moduledoc false

  # One randomized run of a plan: the data written first, then the writers' transactions and the
  # clients' schedules all at once, then every client connected again and the three checks.
  # Answers what each check found, with what the report needs to explain it.
  #
  # The run traps exits while it goes, so a client, writer or schedule that crashes is a failure in
  # the report, with the seed and the trace, rather than one that takes the test down without them.

  import HologramSyncTests.Helpers, only: [create!: 2, read_seq: 0, truncate_tables: 0]

  alias Hologram.DB
  alias Hologram.DB.Oplog
  alias Hologram.Entity.Model, as: EntityModel
  alias Hologram.Sync.Catchup
  alias Hologram.Sync.Cursor
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
  flagged, the rows check 3 found missing below a final limit, the clients' failures and the run's
  own, and the clients whose gap outgrew a replay and who weren't told to start over - with the
  history and each client's events and records for the report.
  """
  @type outcome :: %{
          below_final: list(map),
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

  defp run_step(:reload, pid), do: Client.reload(pid)

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
    aborted = History.aborted(history)
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
      below_final:
        for(
          report <- reports,
          problem <- report.below_final,
          do: Map.put(problem, :client, report.name)
        ),
      clients: reports ++ dead,
      differences:
        for(
          report <- reports,
          difference <- report.differences,
          do: %{client: report.name, difference: difference}
        ),
      failures:
        crashes ++
          unexpected_aborts(aborted) ++
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
      history: %{aborted: aborted, entries: entries},
      leaks:
        for(report <- reports, leak <- report.leaks, do: Map.put(leak, :client, report.name)),
      missed_resyncs: for(report <- reports, missed_resync?(report), do: report.name)
    }
  end

  # A transaction rolled back for a conflict its operations met is part of a run. One rolled back for
  # anything else - an operation failing another way, a lost connection among them, or the lock, the
  # state read or the commit failing after them - isn't, and the workload it left out would go
  # unseen.
  defp unexpected_aborts(aborted) do
    for entry <- aborted, not (entry.stage == :ops and Plan.conflict?(entry.error)) do
      %{client: entry.writer, failure: "rolled back (#{entry.stage}): #{inspect(entry.reason)}"}
    end
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
    {views, final_seq} = Client.final_views(client.pid)

    differences =
      if first_differences == [],
        do: Enum.map(incomplete ++ settled, &{:after_quiet, &1}),
        else: first_differences

    %{
      client
      | below_final: Checks.below_final(views, entries, client.user_id, final_seq),
        differences: differences,
        events: Client.events(client.pid),
        leaks: Checks.leaks(records, entries, client.user_id),
        records: records
    }
  end

  # The server has routed every commit once the dispatcher's read edge reaches the last serial a
  # commit's log entries hold: the edge is the last entry it read.
  defp await_log_read(entries) do
    seqs =
      entries
      |> Enum.map(& &1.max_seq)
      |> Enum.reject(&is_nil/1)

    case seqs do
      [] -> :ok
      seqs -> await(fn -> read_seq() >= Enum.max(seqs) end, @read_ms)
    end
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
  @doc false
  # The client's return is the first connect after its cut: nothing reconnects it while it's away,
  # and a reconnect of its own, or the run's last connect, comes later, from a later place. What
  # answers the return comes on a connection from the same place - the return's own, or one after
  # a stream that ended before the start over was written.
  @spec missed_resync?(%{events: list(map), schedule: list}) :: boolean
  def missed_resync?(report) do
    with true <- :await_writers in report.schedule,
         {connect, after_return} <- return(report.events) do
      gap_too_large?(connect) and
        "gap_too_large" not in resync_reasons(after_return, connect.cursor)
    else
      _no_return -> false
    end
  end

  defp return(events) do
    cut_at =
      events
      |> Enum.with_index()
      |> Enum.filter(fn {event, _index} -> cut?(event) end)
      |> List.last()

    with {_cut, index} <- cut_at,
         {_closed, [connect | rest]} <- split_at_connect(Enum.drop(events, index + 1)) do
      {connect, rest}
    else
      _no_return -> nil
    end
  end

  defp split_at_connect(events), do: Enum.split_while(events, &(&1.kind != :connect))

  defp cut?(event), do: event.kind == :closed and event.cause == :cut

  defp gap_too_large?(%{cursor: cursor}) when is_binary(cursor) do
    case Cursor.decode(cursor) do
      {:ok, {seq, _tx, _at}, _log_id, _policy_hash, _types_hash} ->
        limit = Catchup.gap_limit()
        {count, _other_model?} = Oplog.count_after(seq, limit + 1, EntityModel.hash())

        count > limit

      _no_place ->
        false
    end
  end

  defp gap_too_large?(_no_place), do: false

  # The start overs told on connections from the given place, the first of them already open.
  defp resync_reasons(events, cursor) do
    events
    |> Enum.reduce({cursor, []}, fn
      %{kind: :connect, cursor: from}, {_current, reasons} -> {from, reasons}
      %{frame: "sync_resync", reason: reason}, {^cursor, reasons} -> {cursor, [reason | reasons]}
      _event, acc -> acc
    end)
    |> elem(1)
  end

  # A save left running anywhere on the database server holds the final limit below its serial, and
  # with it every place a session reaches and every number a client is shown - the run would then
  # fail on what that save held back rather than on what it checks. So the log gets a change first,
  # and the run starts once the dispatcher has read past it. The row goes with the truncate after;
  # the change stays in the log.
  #
  # The row's own number, read as stored, rather than the last serial handed out: a save that took
  # one after it and rolled back leaves no entry for the dispatcher to reach.
  defp warm_up_log do
    create!(Tag, name: "warm-up")

    %{rows: [[serial]]} =
      DB.sql!(
        ~s(SELECT "server_created_seq" FROM "hologram_data"."#{DB.table_name(Tag)}" ) <>
          ~s(WHERE "name" = 'warm-up')
      )

    if await(fn -> read_seq() >= serial end, @read_ms) == :timeout do
      raise "a save elsewhere on the database server kept running for #{@read_ms} ms, " <>
              "so the final limit stayed below the run's first change"
    end
  end

  defp start_client(planned, base_url) do
    {:ok, pid} = Client.start_link(base_url: base_url, user_id: planned.user_id)

    Map.merge(planned, %{
      below_final: [],
      differences: [],
      events: [],
      leaks: [],
      pid: pid,
      records: []
    })
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
