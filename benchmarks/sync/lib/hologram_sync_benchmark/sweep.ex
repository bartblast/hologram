defmodule HologramSyncBenchmark.Sweep do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Refactor.IoPuts

  # A case's steps, from the smallest client count up, each on a fresh server node over a freshly
  # vacuumed database with an empty log, stopping at the first step that fails or whose node
  # passes the memory limit. A failing step still reports everything it measured; a stopped one
  # has only the reading it stopped at.

  alias HologramSyncBenchmark.DB
  alias HologramSyncBenchmark.Measure
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Report

  # Marker numbers each step may use, and how many steps fit before the numbers outgrow a marker's
  # seven digits.
  @markers_per_step 100_000

  @max_steps 99

  @default_counts [1, 2, 5, 10, 20, 50, 100, 200, 500, 1_000, 2_000, 5_000]

  @doc """
  Returns the client counts a sweep steps through when none are given.
  """
  @spec default_counts :: [pos_integer]
  def default_counts, do: @default_counts

  @doc """
  Returns how many marker numbers a step may use, the most writes a step can make.
  """
  @spec markers_per_step :: pos_integer
  def markers_per_step, do: @markers_per_step

  @doc """
  Runs the given step for each given client count and returns the results of the steps that ran,
  each with whether it passed, the heap kills the server's log recorded and whether autovacuum
  ran during it.

  `step` runs one step on a server node for a client count, numbering its markers from the
  given first one, and `passed?` judges its result. `summary` turns a result into the line the
  step prints, for a case whose steps measure other things than writes.

  A step whose server node passes `memory_limit` bytes is stopped there, by halting the node, so
  the run can't exhaust the machine. It has no figures, so it's returned apart, as the step that
  stopped the sweep with the reading that stopped it, or nil when none did.
  """
  @spec run(
          pid,
          [pos_integer],
          (Peer.t(), pos_integer, non_neg_integer -> map),
          (map -> boolean),
          (map -> String.t()),
          pos_integer
        ) :: {[map], %{clients: pos_integer, memory: non_neg_integer} | nil}
  def run(conn, counts, step, passed?, summary, memory_limit) do
    if length(counts) > @max_steps do
      raise ArgumentError, "a sweep takes at most #{@max_steps} steps"
    end

    {results, stopped} =
      counts
      |> Enum.with_index()
      |> Enum.reduce_while({[], nil}, fn {count, index}, {results, nil} ->
        conn
        |> run_step(count, index, step, passed?, memory_limit)
        |> take_step(count, results, summary)
      end)

    {Enum.reverse(results), stopped}
  end

  defp gigabytes(bytes), do: Float.round(bytes / 1_073_741_824, 1)

  defp take_step({:stopped, memory}, count, results, _summary) do
    IO.puts("  STOPPED at the memory limit, the server node held #{gigabytes(memory)} GB")

    {:halt, {results, %{clients: count, memory: memory}}}
  end

  defp take_step({:ok, result}, _count, results, summary) do
    result
    |> summary.()
    |> IO.puts()

    next = if result.passed, do: :cont, else: :halt

    {next, {[result | results], nil}}
  end

  # A guard on the server node halts it past the memory limit, and is asked once the step is
  # over whether it did: a node halted while the step only waited, with no call to fail, still
  # makes the step a stopped one, and a step that failed for another reason keeps its error.
  defp run_step(conn, count, index, step, passed?, memory_limit) do
    :ok = DB.truncate_log!(conn)
    :ok = DB.vacuum_analyze!(conn)
    autovacuum_before = DB.autovacuum_runs(conn)

    IO.puts("Step: #{count} clients")

    case Peer.with_peer(&guarded_step(&1, step, count, index, memory_limit)) do
      {:stopped, memory} ->
        {:stopped, memory}

      {:ok, result} ->
        result =
          Map.merge(result, %{
            autovacuum_ran: DB.autovacuum_runs(conn) != autovacuum_before,
            heap_kills: Measure.heap_kills(Peer.log_path()),
            session_cuts: Measure.session_cuts(Peer.log_path())
          })

        {:ok, Map.put(result, :passed, passed?.(result))}
    end
  end

  defp guarded_step(peer, step, count, index, memory_limit) do
    guard = Measure.start_memory_guard(peer, memory_limit)

    outcome =
      try do
        {:ok, step.(peer, count, index * @markers_per_step)}
      catch
        kind, reason -> {:error, kind, reason, __STACKTRACE__}
      end

    # A node gone for another reason, with nothing in the step to fail on it, leaves a step whose
    # figures can't be trusted, so that says so rather than passing as a result.
    case {Measure.stop_memory_guard(guard), outcome} do
      {nil, {:ok, result}} ->
        {:ok, result}

      {answer, {:error, kind, reason, stacktrace}} when answer in [nil, :node_gone] ->
        :erlang.raise(kind, reason, stacktrace)

      {:node_gone, {:ok, _result}} ->
        raise "the server node went down during the step"

      {memory, _outcome} ->
        {:stopped, memory}
    end
  end

  @doc """
  Returns the case's clients-per-node figure from the given step results: the largest client
  count that passed, "at least" it when every step passed and none stopped, "below" the first one
  when none passed. Beside it, the fills the server cut short in the step it names, and the step
  stopped at the memory limit, given in GB, with the reading it stopped at, and why the step that
  ended the sweep failed, which `why` gives for a result.
  """
  @spec figure([map], map | nil, pos_integer, (map -> String.t())) :: String.t()
  def figure(results, stopped, memory_limit_gb, why) do
    {text, named} = figure_text(results, stopped)
    last = List.last(results)

    failed =
      if last && not last.passed,
        do:
          "#{last.clients} #{if last.clients == 1, do: "client", else: "clients"} failed: #{why.(last)}"

    notes =
      named
      |> figure_notes(stopped, memory_limit_gb)
      |> Kernel.++([failed])
      |> Enum.filter(& &1)

    if notes == [], do: text, else: "#{text} (#{Enum.join(notes, "; ")})"
  end

  @doc """
  Returns what went wrong with the given fill, as parts of a step's failure note.
  """
  @spec fill_reasons(map, pos_integer) :: [String.t() | false]
  def fill_reasons(fill, fill_timeout_s) do
    [
      fill.failed > 0 && "#{fill.failed} failed",
      fill.unfinished > 0 && "#{fill.unfinished} never filled",
      fill.connect_failures > 0 && "#{fill.connect_failures} couldn't connect",
      Enum.any?(fill.ms, &(&1 > fill_timeout_s * 1_000)) && "fills over #{fill_timeout_s} s"
    ]
  end

  defp figure_notes(named, stopped, memory_limit_gb) do
    [
      named && named.fill.restarts > 0 &&
        "#{named.fill.restarts} #{if named.fill.restarts == 1, do: "fill", else: "fills"} " <>
          "restarted, #1635",
      stopped &&
        "#{stopped.clients} stopped at the #{memory_limit_gb} GB memory limit, the server node " <>
          "holding #{gigabytes(stopped.memory)} GB"
    ]
  end

  # The figure and the step it names: the largest count that passed, "at least" it when no step
  # failed or stopped, "below" the first count when none passed.
  defp figure_text(results, stopped) do
    passed = Enum.filter(results, & &1.passed)
    last = List.last(results)

    cond do
      passed == [] and last == nil -> {"below #{stopped.clients}", nil}
      passed == [] -> {"below #{last.clients}", last}
      last.passed and stopped == nil -> {"at least #{last.clients}", last}
      true -> {"#{List.last(passed).clients}", List.last(passed)}
    end
  end

  @doc """
  Returns the given client counts in the order a sweep steps through them, smallest first, so
  the largest passing count is the last one that passed.
  """
  @spec sort_counts([pos_integer]) :: [pos_integer]
  def sort_counts(counts) do
    counts
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns the line a step with steady writes prints.
  """
  @spec summary(map) :: String.t()
  def summary(result) do
    %{fill: fill, isolated: isolated, steady: steady} = result

    [
      "  #{if result.passed, do: "passed", else: "FAILED"}",
      "fill p50 #{Report.cell(Measure.percentile(fill.ms, 50))} ms",
      "p99 #{Report.cell(Measure.percentile(fill.ms, 99))} ms",
      "#{fill.filled}/#{result.clients} filled, #{fill.restarts} restarts, " <>
        "#{result.heap_kills} heap kills" <>
        if(result.heap_kills != fill.restarts, do: " (MISMATCH)", else: ""),
      "single write #{Report.cell(isolated.last_delivery_ms)} ms to the last client",
      "steady p99 #{Report.cell(steady.p99_ms)} ms, #{steady.missing} missing, " <>
        "#{steady.leaked} leaked, " <>
        "#{steady.streams_lost} streams lost, #{result.session_cuts} sessions cut",
      "#{Report.cell(steady.cpu_ms_per_write)} CPU ms per write",
      "per write #{Report.cell(steady.db.xact_commit)} commits, " <>
        "#{Report.cell(steady.db.tup_returned)} rows scanned, " <>
        "#{Report.cell(steady.db.tup_fetched)} fetched, " <>
        "#{Report.cell(steady.db.active_ms)} DB ms",
      "#{Report.cell(result.memory_per_client && result.memory_per_client / 1_024)} KB per client"
    ]
    |> Enum.join(", ")
    |> Kernel.<>(if result.autovacuum_ran, do: ", AUTOVACUUM RAN", else: "")
  end
end
