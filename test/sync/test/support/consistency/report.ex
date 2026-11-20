defmodule HologramSyncTests.Consistency.Report do
  @moduledoc false

  # What a failed randomized run tells: a message short enough for CI's log, naming the seed, how
  # to replay it, the first problems with the commits behind each row and the client's connects and
  # cuts, and a trace with everything - the plan, every commit in lock order, each client's events
  # with the rows and pairs it received, and every problem - written to a file CI keeps.

  alias HologramSyncTests.Consistency.Plan

  @shown 5

  @doc """
  Returns whether the given outcome of a run found anything.
  """
  @spec failed?(map) :: boolean
  def failed?(outcome), do: problems(outcome) != []

  @doc """
  Returns the message of a run of the given seed that raised or exited before it could report, at
  any point of the run, with how to replay it and what went wrong, as `Exception.format/3` spells
  it.
  """
  @spec crash_message(
          String.t(),
          %{runs: pos_integer, seed: integer, steps: pos_integer},
          pos_integer
        ) ::
          String.t()
  def crash_message(error, options, run) do
    """
    The randomized sync run failed for seed #{options.seed} (run #{run} of #{options.runs}) before it could report.

    #{replay(options)}

    #{error}
    """
  end

  @doc """
  Returns the message of a failed run of the given seed, the given run of how many, its trace at
  the given path.
  """
  @spec message(
          map,
          %{runs: pos_integer, seed: integer, steps: pos_integer},
          pos_integer,
          String.t()
        ) :: String.t()
  def message(outcome, options, run, path) do
    problems = problems(outcome)

    """
    The randomized sync run failed for seed #{options.seed} (run #{run} of #{options.runs}).
    The plan is random, so this failure may not come from the change under test.

    #{replay(options)}
    Trace: #{path}

    #{summary(outcome)}

    #{explain_first(problems, outcome)}
    """
  end

  @doc """
  Writes the trace of the given run of the given plan into the given directory, named after the
  seed and the run, and returns its path.
  """
  @spec write(map, Plan.t(), pos_integer, String.t()) :: String.t()
  def write(outcome, plan, run, dir) do
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{plan.seed}-#{run}.log")

    File.write!(path, trace(outcome, plan))

    path
  end

  defp replay(options) do
    "Replay: SYNC_SEED=#{options.seed} SYNC_STEPS=#{options.steps} mix test --include randomized " <>
      "test/consistency_test.exs\nA replay gives the same plan, not the same interleaving: " <>
      "SYNC_RUNS=<n> runs it n times."
  end

  defp summary(outcome) do
    "Check 1, stores that differ once the writes stopped: #{length(outcome.differences)}. " <>
      "Check 2, rows received that their user couldn't read then: #{length(outcome.leaks)}. " <>
      "Failures: #{length(outcome.failures)}. " <>
      "Clients away past the gap limit and never told to start over: #{length(outcome.missed_resyncs)}."
  end

  defp problems(outcome) do
    Enum.map(outcome.differences, &{:difference, &1}) ++
      Enum.map(outcome.leaks, &{:leak, &1}) ++
      Enum.map(outcome.failures, &{:failure, &1}) ++
      Enum.map(outcome.missed_resyncs, &{:missed_resync, &1})
  end

  defp explain_first(problems, outcome) do
    problems
    |> Enum.take(@shown)
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", &explain(&1, outcome))
  end

  defp explain({problem, index}, outcome) do
    {client_name, text, row_id} = describe_problem(problem)
    client = Enum.find(outcome.clients, &(&1.name == client_name))

    lines =
      ["#{index}. #{client_name} (user #{inspect(client && client.user_id)}): #{text}"] ++
        commits_touching(row_id, client, outcome) ++ timeline(client)

    Enum.join(lines, "\n")
  end

  defp describe_problem({:difference, %{client: client, difference: difference}}) do
    {text, row_id} = describe_difference(difference)

    {client, text, row_id}
  end

  defp describe_problem({:leak, leak}) do
    record = leak.record

    what =
      if Map.get(record, :pair?, false),
        do: "a pair under #{inspect(record.type)} #{record.id} naming #{inspect(record.named)}",
        else:
          "#{inspect(record.type)} #{record.id} carrying #{inspect(record.carried)}, naming " <>
            inspect(record.named)

    {leak.client,
     "received #{what}, at #{record.received_at}, on a connection opened at " <>
       "#{record.opened_at}, bounded by tx #{inspect(record.cursor_tx)} - in the commits " <>
       "#{inspect(leak.candidates)} the frame could come from, its user could read it with those " <>
       "values in none, or a row it names in none since the connection opened", record.id}
  end

  defp describe_problem({:failure, failure}) do
    {failure.client, "failed: #{inspect(Map.drop(failure, [:at, :client, :kind]))}", nil}
  end

  defp describe_problem({:missed_resync, client}) do
    {client, "came back after the writers were done and was never told to start over", nil}
  end

  defp describe_difference({:after_quiet, difference}) do
    {text, row_id} = describe_difference(difference)

    {"once the stores had converged and the server had read every commit: " <> text, row_id}
  end

  defp describe_difference(:incomplete), do: {"was never told it holds everything", nil}

  defp describe_difference({:missing, type, id, row}) do
    {"misses #{inspect(type)} #{id}, which should be #{inspect(row)}", id}
  end

  defp describe_difference({:extra, type, id, row}) do
    {"holds #{inspect(type)} #{id} as #{inspect(row)}, which its user may not read", id}
  end

  defp describe_difference({:fields, type, id, expected, held}) do
    {"holds #{inspect(type)} #{id} as #{inspect(held)}, not #{inspect(expected)}", id}
  end

  defp describe_difference({:set, type, id, name, expected, held}) do
    {"holds #{inspect(type)} #{id}'s #{name} as #{inspect(held)}, not #{inspect(expected)}", id}
  end

  defp commits_touching(nil, _client, _outcome), do: []

  # The commits naming the row, the rows its access goes through - what its fields point at, and
  # what those point at in turn: a card's board and the board's space, a member's space and user -
  # or the client's user, which grants, removals and blocks name.
  defp commits_touching(row_id, client, outcome) do
    user_ids = if client && client.user_id, do: [client.user_id], else: []
    related = related_ids(row_id, outcome.history.entries) ++ user_ids

    touching =
      for {entry, index} <- Enum.with_index(outcome.history.entries),
          Enum.any?(entry.ops, fn op -> Enum.any?(related, &String.contains?(op, &1)) end),
          do:
            "   commit #{index} (#{entry.writer}, xid #{entry.xid}, lock #{entry.after_lock_at}, " <>
              "committed #{entry.committed_at}): #{Enum.join(entry.ops, "; ")}"

    [
      "  commits naming the row or what its access goes through:"
      | if(touching == [], do: ["   none"], else: touching)
    ]
  end

  defp related_ids(row_id, entries) do
    rows =
      for entry <- entries,
          {_type, by_id} <- entry.state.rows,
          {id, fields} <- by_id,
          reduce: %{} do
        acc -> Map.update(acc, id, field_ids(fields), &MapSet.union(&1, field_ids(fields)))
      end

    hop = fn ids -> Enum.reduce(ids, ids, &MapSet.union(&2, Map.get(rows, &1, MapSet.new()))) end

    [row_id]
    |> MapSet.new()
    |> hop.()
    |> hop.()
    |> MapSet.to_list()
  end

  defp field_ids(fields) do
    for {name, value} <- fields,
        String.ends_with?(name, "_id") and is_binary(value),
        into: MapSet.new(),
        do: value
  end

  defp timeline(nil), do: []

  defp timeline(client) do
    steps =
      for event <- client.events, event.kind in [:connect, :closed] do
        if event.kind == :connect,
          do: "   #{event.at} connect, cursor #{inspect(event.cursor)}",
          else: "   #{event.at} closed: #{inspect(event.cause)}"
      end

    ["  its connects and closes:" | steps]
  end

  defp trace(outcome, plan) do
    [
      "SEED #{plan.seed}",
      "",
      "DATA WRITTEN FIRST",
      Enum.map(plan.seed_ops, &"  #{Plan.describe(&1)}"),
      "",
      "PLANNED TRANSACTIONS",
      for(
        writer <- plan.writers,
        transaction <- writer.transactions,
        do: "  #{transaction.order} #{writer.name}: #{describe_ops(transaction)}"
      ),
      "",
      "COMMITS IN LOCK ORDER",
      for(
        {entry, index} <- Enum.with_index(outcome.history.entries),
        do:
          "  #{index} #{entry.writer} xid #{entry.xid} at #{entry.after_lock_at}..#{entry.committed_at}: " <>
            Enum.join(entry.ops, "; ")
      ),
      "",
      "ROLLED BACK",
      Enum.map(
        outcome.history.aborted,
        &("  #{&1.writer} (#{Map.get(&1, :stage, :ops)}): #{Enum.join(&1.ops, "; ")} - " <>
            spell_reason(&1.reason))
      ),
      "",
      "CLIENTS",
      Enum.map(outcome.clients, &client_trace/1),
      "",
      "PROBLEMS",
      problem_lines(outcome)
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp problem_lines(outcome) do
    outcome
    |> problems()
    |> Enum.map(&"  #{inspect(&1, limit: :infinity)}")
  end

  # A rollback's reason is an exception's message, or whatever else the transaction rolled back
  # with, like `:rollback`, which isn't a string.
  defp spell_reason(reason) when is_binary(reason), do: reason

  defp spell_reason(reason), do: inspect(reason)

  defp describe_ops(transaction) do
    transaction.ops
    |> Enum.zip(transaction.holds)
    |> Enum.map_join("; ", fn {op, hold} -> "#{Plan.describe(op)} (hold #{hold} ms)" end)
  end

  # A client's events and the rows and pairs it received, in the order of the monotonic clock both
  # read. A row's time is the arrival of the chunk that completed its frame, read before the events
  # of that chunk's frames, so a chunk's rows come right before its frames' events, each in the
  # order it arrived - a frame's ops count how many of them it brought.
  defp client_trace(client) do
    received = Enum.map(client.records, &received_entry/1)
    events = Enum.map(client.events, &Map.drop(&1, [:request_id]))

    [
      "  #{client.name}, user #{inspect(client.user_id)}, schedule #{inspect(client.schedule)}",
      (received ++ events)
      |> Enum.sort_by(& &1.at)
      |> Enum.map(&"    #{inspect(&1, limit: :infinity)}")
    ]
  end

  defp received_entry(record) do
    record
    |> Map.drop([:opened_at, :received_at])
    |> Map.merge(%{at: record.received_at, kind: :received})
  end
end
