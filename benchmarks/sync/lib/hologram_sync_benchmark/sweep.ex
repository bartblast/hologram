defmodule HologramSyncBenchmark.Sweep do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Refactor.IoPuts

  # A case's steps, from the smallest client count up, each on a fresh server node over a freshly
  # vacuumed database with an empty log, stopping at the first step that fails. A failing step
  # still reports everything it measured.

  alias HologramSyncBenchmark.DB
  alias HologramSyncBenchmark.Measure
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Report

  # Marker numbers each step may use, and how many steps fit before the numbers outgrow a marker's
  # seven digits.
  @markers_per_step 100_000

  @max_steps 99

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
  given first one, and `passed?` judges its result.
  """
  @spec run(
          pid,
          [pos_integer],
          (Peer.t(), pos_integer, non_neg_integer -> map),
          (map -> boolean)
        ) :: [map]
  def run(conn, counts, step, passed?) do
    if length(counts) > @max_steps do
      raise ArgumentError, "a sweep takes at most #{@max_steps} steps"
    end

    counts
    |> Enum.with_index()
    |> Enum.reduce_while([], fn {count, index}, results ->
      :ok = DB.truncate_log!(conn)
      :ok = DB.vacuum_analyze!(conn)
      autovacuum_before = DB.autovacuum_runs(conn)

      IO.puts("Step: #{count} clients")
      result = Peer.with_peer(&step.(&1, count, index * @markers_per_step))

      result =
        Map.merge(result, %{
          autovacuum_ran: DB.autovacuum_runs(conn) != autovacuum_before,
          heap_kills: Measure.heap_kills(Peer.log_path())
        })

      result = Map.put(result, :passed, passed?.(result))

      result
      |> summary()
      |> IO.puts()

      if result.passed, do: {:cont, [result | results]}, else: {:halt, [result | results]}
    end)
    |> Enum.reverse()
  end

  @doc """
  Returns the case's clients-per-node figure from the given step results: the largest client
  count that passed, "at least" it when every step passed, "below" the first one when none did,
  with the fills the server cut short in the step it names beside it.
  """
  @spec figure([map]) :: String.t()
  def figure(results) do
    {text, named} =
      case {Enum.filter(results, & &1.passed), List.last(results)} do
        {[], first_failed} -> {"below #{first_failed.clients}", first_failed}
        {passed, %{passed: true}} -> {"at least #{List.last(passed).clients}", List.last(passed)}
        {passed, _failed} -> {"#{List.last(passed).clients}", List.last(passed)}
      end

    restarts = named.fill.restarts

    if restarts > 0, do: "#{text} (#{restarts} fills restarted, #1635)", else: text
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

  defp summary(result) do
    %{fill: fill, isolated: isolated, steady: steady} = result

    [
      "  #{if result.passed, do: "passed", else: "FAILED"}",
      "fill p50 #{Report.cell(Measure.percentile(fill.ms, 50))} ms",
      "p99 #{Report.cell(Measure.percentile(fill.ms, 99))} ms",
      "#{fill.filled}/#{result.clients} filled, #{fill.restarts} restarts, " <>
        "#{result.heap_kills} heap kills" <>
        if(result.heap_kills != fill.restarts, do: " (MISMATCH)", else: ""),
      "single write #{Report.cell(isolated.last_delivery_ms)} ms to the last client",
      "steady p99 #{Report.cell(steady.p99_ms)} ms, #{steady.missing} missing",
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
