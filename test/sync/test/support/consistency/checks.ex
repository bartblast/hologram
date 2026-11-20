defmodule HologramSyncTests.Consistency.Checks do
  @moduledoc false

  # The consistency checks. The first: once writes stop, a client holds exactly what its user may
  # read - every row, with its current fields and sets, and nothing more. The second: every row a
  # client received was one its user could read, with the values it carried, in a state the server
  # could have read it from.

  alias HologramSyncTests.Consistency.Client
  alias HologramSyncTests.Consistency.Model

  @typedoc """
  One way a client's store differs from what it should hold.
  """
  @type difference ::
          :incomplete
          | {:missing, module, String.t(), map}
          | {:extra, module, String.t(), map}
          | {:fields, module, String.t(), expected :: map, held :: map}
          | {:set, module, String.t(), String.t(), expected :: list, held :: list}

  @doc """
  Polls until the given client says it holds everything and its store equals what its user may
  read in the tables' current state, for at most the given milliseconds. Answers the differences
  left when the time runs out, led by `:incomplete` when the client was still waiting to be told
  it holds everything.
  """
  @spec await_converged(pid, String.t() | nil, non_neg_integer) ::
          :ok | {:error, list(difference)}
  def await_converged(client, user_id, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    poll_converged(client, user_id, deadline)
  end

  @doc """
  Returns the records of the given client's user, from `Client.records/1`, that no state the frame
  could have been read from explains: none in which the user could read the row with every field
  the record carried.

  A frame could have been read from a state when the state could have committed before the frame
  arrived (its transaction got the commit lock before then), could still have been current when the
  connection carrying the frame opened (no later state had committed by the open),
  and, with a bounding transaction id - the frame's cursor's, or the place the client held when it
  arrived - is at or after every state left by a transaction below it: the server read that place
  before the frame's rows, and every transaction below it had ended by then.
  Each violation names the record and the states that bounded it, by position in the history.
  """
  @spec leaks(list(map), list(map), String.t() | nil) :: list(map)
  def leaks(records, entries, user_id) do
    indexed =
      entries
      |> with_superseded_at()
      |> Enum.with_index()

    Enum.flat_map(records, &leak(&1, indexed, user_id))
  end

  @doc """
  Returns how the given store differs from the given expected rows, both in the shape
  `Model.expected/2` answers, sorted by type and id.
  """
  @spec diff(map, map) :: list(difference)
  def diff(store, expected) do
    differences =
      Enum.flat_map(Model.types(), fn type ->
        held = Map.get(store, type, %{})
        wanted = Map.get(expected, type, %{})

        (Map.keys(held) ++ Map.keys(wanted))
        |> Enum.uniq()
        |> Enum.flat_map(&row_diff(type, &1, Map.get(wanted, &1), Map.get(held, &1)))
      end)

    Enum.sort_by(differences, fn difference -> {elem(difference, 1), elem(difference, 2)} end)
  end

  defp poll_converged(client, user_id, deadline) do
    store_differences = diff(Client.store(client), Model.expected(Model.snapshot(), user_id))

    differences =
      if Client.complete?(client), do: store_differences, else: [:incomplete | store_differences]

    cond do
      differences == [] ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, differences}

      true ->
        Process.sleep(50)
        poll_converged(client, user_id, deadline)
    end
  end

  defp candidates(record, indexed) do
    floor = cursor_floor(record.cursor_tx, indexed)

    Enum.filter(indexed, fn {entry, index} ->
      entry.after_lock_at < record.received_at and index >= floor and
        (entry.superseded_at == :infinity or entry.superseded_at >= record.opened_at)
    end)
  end

  # The position of the last state a transaction below the cursor left - the earliest state the
  # frame's rows can be from.
  defp cursor_floor(nil, _indexed), do: 0

  defp cursor_floor(cursor_tx, indexed) do
    indexed
    |> Enum.filter(fn {entry, _index} -> entry.xid < cursor_tx end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.max(fn -> 0 end)
  end

  defp explains?(entry, record, user_id) do
    row = get_in(entry.state, [:rows, record.type, record.id])

    row != nil and Enum.all?(record.carried, fn {name, value} -> Map.get(row, name) == value end) and
      Model.readable?(entry.state, user_id, record.type, record.id)
  end

  defp leak(record, indexed, user_id) do
    candidates = candidates(record, indexed)

    if Enum.any?(candidates, fn {entry, _index} -> explains?(entry, record, user_id) end) do
      []
    else
      [%{candidates: Enum.map(candidates, &elem(&1, 1)), record: record, user_id: user_id}]
    end
  end

  # When each state stopped being current at the latest: the earliest commit time of any later
  # state, since writers read their commit times apart and a later state's can be read first. The
  # last state is current still.
  defp with_superseded_at(entries) do
    {superseded, _earliest} =
      entries
      |> Enum.reverse()
      |> Enum.map_reduce(:infinity, fn entry, earliest_later ->
        {Map.put(entry, :superseded_at, earliest_later),
         min_time(entry.committed_at, earliest_later)}
      end)

    Enum.reverse(superseded)
  end

  defp min_time(time, :infinity), do: time

  defp min_time(time, other), do: min(time, other)

  defp row_diff(_type, _id, nil, nil), do: []

  defp row_diff(type, id, wanted, nil), do: [{:missing, type, id, wanted}]

  defp row_diff(type, id, nil, held), do: [{:extra, type, id, held}]

  defp row_diff(type, id, wanted, held) do
    set_names =
      type
      |> Model.sets()
      |> Map.keys()

    {wanted_sets, wanted_fields} = Map.split(wanted, set_names)
    {held_sets, held_fields} = Map.split(held, set_names)

    fields =
      if wanted_fields == held_fields,
        do: [],
        else: [{:fields, type, id, wanted_fields, held_fields}]

    sets =
      for name <- set_names,
          Map.get(wanted_sets, name) != Map.get(held_sets, name),
          do: {:set, type, id, name, Map.get(wanted_sets, name), Map.get(held_sets, name)}

    fields ++ sets
  end
end
