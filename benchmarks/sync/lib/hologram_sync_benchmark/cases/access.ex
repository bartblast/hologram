defmodule HologramSyncBenchmark.Cases.Access do
  @moduledoc false

  # One write that changes who may read thousands of rows: a project's members read its docs
  # while it isn't archived, every member is connected, and archiving the project hides every doc
  # from every one of them. Then unarchiving it shows them all again. Each step times both from
  # the commit until the last client has heard of every doc, and what each cost the server and
  # the database. The sweep steps through how many members the project has.

  alias HologramSyncBenchmark.Client
  alias HologramSyncBenchmark.Clients
  alias HologramSyncBenchmark.DB
  alias HologramSyncBenchmark.Entities.Doc
  alias HologramSyncBenchmark.Entities.Project
  alias HologramSyncBenchmark.Measure
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Report
  alias HologramSyncBenchmark.Seed
  alias HologramSyncBenchmark.Seeding
  alias HologramSyncBenchmark.Step
  alias HologramSyncBenchmark.Sweep
  alias HologramSyncBenchmark.Writer

  @counts [1, 2, 5, 10, 20, 50, 100]

  @poll_ms 100

  # How long a write may take to reach every client before the step stops waiting. A change
  # waits twice its pass limit when that's longer, so a slow change is still timed rather than
  # cut off.
  @wait_ms 120_000

  # A few writes before anything is measured, so the node's pooled connections and caches are
  # warm, as the other cases' steps do.
  @warmup_writes 3

  @doc """
  Returns the access case for the given options.
  """
  @spec sweep_case(keyword) :: map
  def sweep_case(opts) do
    %{
      check!: fn _counts -> check!(opts) end,
      clients: "signed-in clients, one per member of the project",
      counts: @counts,
      name: "access",
      options: [
        "one project with #{opts[:docs]} docs read with `allow :read, when: project.archived " <>
          "== false and any(member <- project.members, member.user_id == user_id())`, " <>
          "every member connected",
        "a step archives the project, hiding every doc from every client, then unarchives it, " <>
          "and passes when every client fills within #{opts[:fill_timeout]} s and has heard of " <>
          "every doc within #{opts[:access_limit]} s each way"
      ],
      passed?: &passed?(&1, opts),
      seed: &seed(&1, &2, opts),
      step: &step(&1, &2, &3, &4, &5, opts),
      step_options: [],
      summary: &summary/1,
      why: &why_failed(&1, opts),
      tables: &tables/1,
      title: "One write changing access to many rows"
    }
  end

  # Stops at the first client that failed: its stream is gone, so it will never count anything
  # again, and waiting the whole while for it only stretches the step.
  defp await_counts(clients, kind, targets, deadline) do
    reports = Enum.map(clients, &Client.report/1)

    done? =
      reports
      |> Enum.zip(targets)
      |> Enum.all?(fn {report, target} -> report.counted[kind] >= target end)

    cond do
      done? ->
        true

      Enum.any?(reports, &(&1.failure != nil)) ->
        false

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(@poll_ms)
        await_counts(clients, kind, targets, deadline)
    end
  end

  # Archiving or unarchiving the project, timed from its commit until every client has counted
  # every doc arriving as the delta that change makes: each client's target is what it had
  # counted before plus every doc.
  defp change(peer, clients, conn, project_id, archived, kind, opts) do
    docs = opts[:docs]
    wait_ms = max(@wait_ms, opts[:access_limit] * 2_000)
    targets = Enum.map(clients, &(Client.report(&1).counted[kind] + docs))

    stats_before = DB.settled_stats(conn)
    cpu_before = Measure.cpu_sample(peer)
    poller = Measure.start_memory_peak(peer)

    committed_at = Peer.rpc(peer, Writer, :update, [Project, project_id, :archived, archived])
    done? = await_counts(clients, kind, targets, System.monotonic_time(:millisecond) + wait_ms)

    cpu_after = Measure.cpu_sample(peer)
    peak = Measure.stop_memory_peak(poller)
    stats_after = DB.settled_stats(conn)

    last_at =
      clients
      |> Enum.map(&Client.report(&1).counted_at[kind])
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> nil end)

    raw = %{
      cpu_ms: Measure.cpu_ms(cpu_before, cpu_after),
      db: DB.stats_delta(stats_after, stats_before),
      done?: done?,
      elapsed_ms: Measure.elapsed_ms(cpu_before, cpu_after),
      memory_rise: peak,
      ms: if(done? and last_at, do: (last_at - committed_at) / 1_000)
    }

    {raw, stats_after}
  end

  # Docs for the warm-up writes to go to.
  defp check!(opts) do
    if opts[:docs] < @warmup_writes do
      raise ArgumentError, "--docs must be at least #{@warmup_writes}"
    end

    :ok
  end

  # A change that never finished has no CPU figure: its window ran to the wait's end, mostly
  # idle, and taking the idle rate off that leaves noise.
  defp finish(%{done?: false, db: nil} = skipped, _idle), do: skipped

  defp finish(raw, idle) do
    cpu_ms = if raw.done?, do: raw.cpu_ms - idle.cpu_ms_per_ms * raw.elapsed_ms

    %{raw | cpu_ms: cpu_ms, db: Step.adjust(raw.db, idle.db)}
  end

  # A change not made, since the one before it didn't reach everyone.
  defp skipped, do: %{cpu_ms: nil, db: nil, done?: false, memory_rise: nil, ms: nil}

  defp db_figure(%{db: nil}, _key), do: nil

  defp db_figure(%{db: db}, key), do: Map.fetch!(db, key)

  defp megabytes(nil), do: nil

  defp megabytes(bytes), do: bytes / 1_048_576

  defp passed?(result, opts) do
    %{fill: fill, hide: hide, show: show} = result
    limit_ms = opts[:access_limit] * 1_000

    filled? =
      fill.failed == 0 and fill.unfinished == 0 and fill.connect_failures == 0 and
        Enum.all?(fill.ms, &(&1 <= opts[:fill_timeout] * 1_000))

    filled? and result.warmup_cut_short == 0 and hide.done? and show.done? and
      hide.ms <= limit_ms and show.ms <= limit_ms
  end

  defp why_failed(result, opts) do
    %{fill: fill, hide: hide, show: show} = result
    limit_ms = opts[:access_limit] * 1_000

    # A change is only made after the one before it reached everyone, so one not made isn't a
    # reason of its own.
    filled? = fill.failed == 0 and fill.unfinished == 0 and fill.connect_failures == 0

    [
      Sweep.fill_reasons(fill, opts[:fill_timeout]),
      result.warmup_cut_short > 0 &&
        "#{result.warmup_cut_short} warm-up writes never reached everyone",
      filled? && change_reason("archive", hide, limit_ms),
      hide.done? && change_reason("unarchive", show, limit_ms)
    ]
    |> List.flatten()
    |> Enum.filter(& &1)
    |> Enum.join(", ")
  end

  defp change_reason(name, %{done?: false}, _limit_ms), do: "the #{name} never reached everyone"

  defp change_reason(name, %{ms: ms}, limit_ms) when ms > limit_ms,
    do: "the #{name} took #{round(ms)} ms"

  defp change_reason(_name, _change, _limit_ms), do: nil

  defp seed(conn, max_count, opts) do
    {_seeding, {table, user_ids, project_id}} =
      Seeding.seed!(conn, fn peer ->
        {user_ids, project_id} = Peer.rpc(peer, Seed, :project, [max_count, opts[:docs]])

        {Seeding.table_name(peer, Doc), user_ids, project_id}
      end)

    :ok = Seeding.check_rows!(conn, table, opts[:docs])

    %{cookie_paths: Enum.map(user_ids, &"/sign_in/#{&1}"), project_id: project_id}
  end

  defp step(conn, peer, count, first_marker, context, opts) do
    base = Clients.base_opts(peer, "HologramSyncBenchmark.DocsPage")

    clients =
      context.cookie_paths
      |> Enum.take(count)
      |> Enum.map(&Keyword.merge(base, cookie_path: &1, count_type: inspect(Doc)))
      |> Clients.start_all()

    try do
      Clients.prepare_all!(clients, Step.connect_concurrency())

      memory_before = Measure.memory(peer, collect: true)
      fill = Step.fill(peer, clients, %{conn: conn, fill_timeout_ms: opts[:fill_timeout] * 1_000})
      memory_after = Measure.memory(peer)

      # A change is only made once the one before it reached everyone: a client that never
      # filled, or never heard of the archive, can't tell anything about the next change, and
      # waiting for it would only stretch the step.
      filled? = fill.failed == 0 and fill.unfinished == 0 and fill.connect_failures == 0

      warmup_cut_short = if filled?, do: warm_up(peer, clients, first_marker), else: 0

      {hide, stats_after_hide} =
        if filled? do
          change(peer, clients, conn, context.project_id, true, :unsync, opts)
        else
          {skipped(), DB.settled_stats(conn)}
        end

      {show, stats_after_show} =
        if hide.done? do
          change(peer, clients, conn, context.project_id, false, :put, opts)
        else
          {skipped(), stats_after_hide}
        end

      idle = Step.idle(peer, %{conn: conn}, stats_after_show)

      %{
        clients: count,
        fill: %{
          fill
          | cpu_ms: fill.cpu_ms - idle.cpu_ms_per_ms * fill.cpu_elapsed_ms,
            db: Step.adjust(fill.db, idle.db)
        },
        hide: finish(hide, idle),
        memory_per_client:
          if(count >= Step.memory_min_clients(), do: (memory_after - memory_before) / count),
        show: finish(show, idle),
        warmup_cut_short: warmup_cut_short
      }
    after
      Clients.close_all(clients)
    end
  end

  defp summary(result) do
    %{hide: hide, show: show} = result

    "  #{if result.passed, do: "passed", else: "FAILED"}, " <>
      "#{result.fill.filled}/#{result.clients} filled, " <>
      "hide #{Report.cell(hide.ms)} ms, #{Report.cell(hide.cpu_ms)} CPU ms, " <>
      "show #{Report.cell(show.ms)} ms, #{Report.cell(show.cpu_ms)} CPU ms, " <>
      "memory rise #{Report.cell(megabytes(hide.memory_rise))} MB hiding, " <>
      "#{Report.cell(megabytes(show.memory_rise))} MB showing, " <>
      "#{result.heap_kills} heap kills, #{result.session_cuts} sessions cut" <>
      if(result.autovacuum_ran, do: ", AUTOVACUUM RAN", else: "")
  end

  defp tables(results) do
    [
      {"Fill", Report.fill_columns(), Enum.map(results, &Report.fill_row/1)},
      {"Archive, then unarchive", change_columns(), Enum.map(results, &change_row/1)}
    ]
  end

  defp change_columns do
    [
      "Clients",
      "Hide ms",
      "Hide CPU ms",
      "Hide DB commits",
      "Hide DB rows scanned",
      "Hide DB ms",
      "Show ms",
      "Show CPU ms",
      "Show DB commits",
      "Show DB rows scanned",
      "Show DB ms",
      "Hide memory rise MB",
      "Show memory rise MB",
      "Step passed"
    ]
  end

  defp change_row(result) do
    %{hide: hide, show: show} = result

    [
      result.clients,
      hide.ms,
      hide.cpu_ms,
      db_figure(hide, :xact_commit),
      db_figure(hide, :tup_returned),
      db_figure(hide, :active_ms),
      show.ms,
      show.cpu_ms,
      db_figure(show, :xact_commit),
      db_figure(show, :tup_returned),
      db_figure(show, :active_ms),
      megabytes(hide.memory_rise),
      megabytes(show.memory_rise),
      Report.passed_cell(result)
    ]
  end

  # Doc titles set to markers, each waited on until every client has it. Returns how many never
  # reached everyone.
  defp warm_up(peer, clients, first_marker) do
    ids = Peer.rpc(peer, Writer, :ids, [Doc])

    Enum.count(0..(@warmup_writes - 1), fn offset ->
      number = first_marker + offset
      Peer.rpc(peer, Writer, :update, [Doc, elem(ids, offset), :title, Client.marker(number)])

      deadline = System.monotonic_time(:millisecond) + @wait_ms
      not await_marker(clients, number, deadline)
    end)
  end

  # Gives up on a failed client too, for the same reason as await_counts/4.
  defp await_marker(clients, number, deadline) do
    cond do
      Enum.all?(clients, &Client.has_marker?(&1, number)) ->
        true

      Enum.any?(clients, &(Client.report(&1).failure != nil)) ->
        false

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(@poll_ms)
        await_marker(clients, number, deadline)
    end
  end
end
