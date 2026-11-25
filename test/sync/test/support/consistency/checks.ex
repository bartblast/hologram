defmodule HologramSyncTests.Consistency.Checks do
  @moduledoc false

  # The consistency checks. The first: once writes stop, a client holds exactly what its user may
  # read - every row, with its current fields and sets, and nothing more. The second: every row a
  # client received was one its user could read, with the values it carried, in a state the server
  # could have read it from, and every row its sets or a pair named one its user could read since
  # the connection opened. The third: a client told the numbers are final up to a limit holds every
  # row its user could read throughout, and that no change still on its way names, with a number at
  # or below it, showing that number - so no list of its ordered by number skips one - and once the
  # writes stop, the limit reaches the last commit.

  alias HologramSyncTests.Consistency.Client
  alias HologramSyncTests.Consistency.Model
  alias HologramSyncTests.Entities.Board
  alias HologramSyncTests.Entities.Card

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
  the record carried, or a row its sets or its pair named that the user could read in none of them.
  Each named row is judged on its own: a row handed over whole carries sets built from what the
  session takes the client to hold, which can be read a moment apart from the row's values.

  A frame could have been read from a state when the state could have committed before the frame
  arrived (its transaction got the commit lock before then), could still have been current when the
  connection carrying the frame opened (no later state had committed by the open), and, with a
  bounding serial - the seq of the frame's cursor, or of the place the client held when it arrived
  - is at or after every state left by a transaction holding a serial at or below it: the server
  read that place before the frame's rows, and every save holding one had ended by then.
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
  Returns what check 3 finds in the given views of a client of the given user, from
  `Client.final_views/1`, given the history's entries and the limit the client held once the writes
  stopped and the server had read every commit, or nil.

  Each view names a limit per type: the one every type has, which the server tells only once it
  sent every change holding a serial at or below it, or a higher one a fill's marker gave its type,
  told once the fill sent every row of the type. A type still filling is judged by the first, so a
  limit vouching for rows that haven't come yet shows up here. Saves take their serials before the
  commit lock, so they can lock out of serial order, and the server sends effects in serial order.
  A commit holding a serial at or below the limit ended before the server told it, and so did
  every commit that locked before it, so the state the last such commit in lock order left - the
  floor - is the client's to know, save for what a commit holding a serial above the limit did,
  which may yet be on its way. A row of the type, with a created number at or below its limit,
  that its user could read in the floor and in every state after it whose transaction got the
  commit lock before the frame arrived, so that nothing still on its way could have taken it away,
  and that no commit holding a serial above the limit and locked before the frame arrived names,
  along with what its access goes through, has to be in the view, showing that number - and, when
  its updated number is the same in all those states and at or below the limit, that one too.

  A commit is judged by its ops as a whole, so one holding serials on both sides of the limit
  keeps the rows any of its ops names from being judged, even through the ops it took at or below
  the limit.

  A number a view shows is one a reader finds, so it is always at or below its type's limit, and
  a type with none shows no number.

  Answers each row missing or showing other numbers, or showing one above its type's limit, by the
  view's time and the type's limit, and a limit held at the end that stops short of the last
  commit's serials.
  """
  @spec below_final(list(map), list(map), String.t() | nil, non_neg_integer | nil) :: list(map)
  def below_final(views, entries, user_id, final_seq) do
    indexed = Enum.with_index(entries)

    Enum.flat_map(views, &view_problems(&1, indexed, user_id)) ++ not_final(entries, final_seq)
  end

  @doc """
  Returns the ids of the given row and of the rows its access goes through - what its fields point
  at, and what those point at in turn: a card's board and the board's space, a member's space and
  user - across all the given history entries.
  """
  @spec related_ids(String.t(), list(map)) :: list(String.t())
  def related_ids(row_id, entries) do
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
    {complete?, store} = Client.view(client)
    store_differences = diff(store, Model.expected(Model.snapshot(), user_id))

    differences = if complete?, do: store_differences, else: [:incomplete | store_differences]

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

  defp view_problems(view, indexed, user_id) do
    above_final(view) ++ missing_or_misnumbered(view, indexed, user_id)
  end

  # A number an earlier fill's type marker filed stays after a refill takes the marker's limit, so
  # it's judged by the higher of the two.
  defp above_final(view) do
    for {type, rows} <- view.rows,
        final_seq <- [proven_final(view, type)],
        {id, shown} <- rows,
        {created_seq, updated_seq} = shown,
        above?(created_seq, final_seq) or above?(updated_seq, final_seq),
        do: %{
          at: view.at,
          final_seq: final_seq,
          id: id,
          problem: :above_final,
          shown: shown,
          type: type
        }
  end

  defp proven_final(view, type) do
    case Enum.reject([Map.get(view.finals, type), get_in(view, [:proven, type])], &is_nil/1) do
      [] -> nil
      points -> Enum.max(points)
    end
  end

  defp above?(nil, _final_seq), do: false

  defp above?(_seq, nil), do: true

  defp above?(seq, final_seq), do: seq > final_seq

  defp missing_or_misnumbered(view, indexed, user_id) do
    Enum.flat_map(view.finals, fn {type, final_seq} ->
      type_missing_or_misnumbered(view, indexed, user_id, type, final_seq)
    end)
  end

  defp type_missing_or_misnumbered(view, indexed, user_id, type, final_seq) do
    # A commit holding a serial at or below the limit ended before the limit was published, so one
    # locked after the frame arrived breaks the limit, and the row it would hide is judged.
    locked_before = Enum.filter(indexed, fn {entry, _index} -> entry.after_lock_at < view.at end)

    case serial_floor(final_seq, locked_before) do
      nil ->
        []

      floor ->
        window =
          Enum.filter(indexed, fn {entry, index} ->
            index == floor or (index > floor and entry.after_lock_at < view.at)
          end)

        {floor_entry, _floor} = Enum.find(window, &(elem(&1, 1) == floor))

        for {id, {created_seq, _updated_seq}} <- seqs_of(floor_entry.state, type),
            created_seq <= final_seq,
            readable_throughout?(window, user_id, type, id),
            problem = row_problem(view, window, type, id, created_seq, final_seq),
            problem != nil,
            not touched_above?(indexed, view.at, final_seq, user_id, type, id),
            do:
              Map.merge(problem, %{
                at: view.at,
                final_seq: final_seq,
                floor: floor,
                id: id,
                type: type
              })
    end
  end

  # What a commit holding a serial above the limit did may not have reached the client yet: the
  # server sends effects in serial order, so one locked up to the floor - the floor's own commit can
  # hold serials on both sides - may still be on its way, and the server reads what a gained access
  # lets through from the live tables, so one locked after the floor can keep a row from coming
  # until its own effect does. Every such commit that matters locked before the frame arrived, the
  # floor's among them. When one names the row or what its access went through by then, the client
  # may rightly not hold the row yet. A type-wide grant or revoke names only the user, and changes
  # only who reads boards and the cards on them.
  defp touched_above?(indexed, at, final_seq, user_id, type, id) do
    above =
      for {entry, _index} <- indexed,
          entry.after_lock_at < at and entry.max_seq != nil and entry.max_seq > final_seq,
          do: entry

    case above do
      [] ->
        false

      above ->
        names =
          related_ids(id, for({entry, _index} <- indexed, entry.after_lock_at < at, do: entry))

        wide? = type in [Board, Card]

        Enum.any?(above, &(names_any?(&1, names) or (wide? and names_wide?(&1, user_id))))
    end
  end

  @doc """
  Tells whether any op of the given history entry names any of the given ids.
  """
  @spec names_any?(map, list(String.t())) :: boolean
  def names_any?(entry, names) do
    entry
    |> Map.get(:ops, [])
    |> Enum.any?(fn op -> Enum.any?(names, &String.contains?(op, &1)) end)
  end

  defp names_wide?(_entry, nil), do: false

  defp names_wide?(entry, user_id) do
    entry
    |> Map.get(:ops, [])
    |> Enum.any?(fn op ->
      (String.starts_with?(op, "grant_wide ") or String.starts_with?(op, "revoke_wide ")) and
        String.contains?(op, user_id)
    end)
  end

  defp field_ids(fields) do
    for {name, value} <- fields,
        String.ends_with?(name, "_id") and is_binary(value),
        into: MapSet.new(),
        do: value
  end

  defp readable_throughout?(window, user_id, type, id) do
    Enum.all?(window, fn {entry, _index} -> Model.readable?(entry.state, user_id, type, id) end)
  end

  defp row_problem(view, window, type, id, created_seq, final_seq) do
    shown = get_in(view.rows, [type, id])

    updated_seq = steady_updated_seq(window, type, id, final_seq)

    cond do
      shown == nil ->
        %{problem: :missing, wanted: {created_seq, updated_seq}}

      elem(shown, 0) != created_seq ->
        %{problem: :numbers, shown: shown, wanted: {created_seq, updated_seq}}

      updated_seq != nil and elem(shown, 1) != updated_seq ->
        %{problem: :numbers, shown: shown, wanted: {created_seq, updated_seq}}

      true ->
        nil
    end
  end

  # The row's updated number when it's the same throughout the window and at or below the limit,
  # else nil.
  defp steady_updated_seq(window, type, id, final_seq) do
    updated_seqs =
      window
      |> Enum.map(fn {entry, _index} -> updated_seq(entry.state, type, id) end)
      |> Enum.uniq()

    case updated_seqs do
      [seq] when seq <= final_seq -> seq
      _moved_or_held -> nil
    end
  end

  defp updated_seq(state, type, id) do
    {_created_seq, updated_seq} =
      state
      |> seqs_of(type)
      |> Map.get(id, {nil, nil})

    updated_seq
  end

  # The last commit's serials are final once the writes stopped and the server read it.
  defp not_final(entries, final_seq) do
    last_seq =
      entries
      |> Enum.map(& &1.max_seq)
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> nil end)

    if last_seq != nil and (final_seq == nil or final_seq < last_seq),
      do: [%{final_seq: final_seq, last_seq: last_seq, problem: :not_final}],
      else: []
  end

  defp seqs_of(state, type) do
    state
    |> Map.get(:seqs, %{})
    |> Map.get(type, %{})
  end

  defp candidates(record, indexed) do
    floor = serial_floor(record.cursor_seq, indexed) || 0

    record
    |> open_candidates(indexed)
    |> Enum.filter(fn {_entry, index} -> index >= floor end)
  end

  # The states current at some point between the connection opening and the frame arriving, with no
  # floor: a row a set or a pair names is one the session holds, readable when it read or told it,
  # which can be a state below the frame's place - but never one from before the connection.
  defp open_candidates(record, indexed) do
    Enum.filter(indexed, fn {entry, _index} ->
      entry.after_lock_at < record.received_at and
        (entry.superseded_at == :infinity or entry.superseded_at >= record.opened_at)
    end)
  end

  # The position of the last state a transaction holding a serial at or below the given one left -
  # the earliest state the server can have read once every save holding one had ended. Nil without
  # a serial, or when no such transaction committed.
  defp serial_floor(nil, _indexed), do: nil

  defp serial_floor(seq, indexed) do
    indexed
    |> Enum.filter(fn {entry, _index} -> entry.min_seq != nil and entry.min_seq <= seq end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.max(fn -> nil end)
  end

  defp explains?(entry, record, user_id) do
    row = get_in(entry.state, [:rows, record.type, record.id])

    row != nil and Enum.all?(record.carried, fn {name, value} -> Map.get(row, name) == value end) and
      Model.readable?(entry.state, user_id, record.type, record.id)
  end

  # Every row a record's sets or pair named has to be one the user could read in some state since
  # the connection opened.
  defp named_readable?(open, user_id, record) do
    Enum.all?(record.named, fn {type, id} -> readable_in_any?(open, user_id, type, id) end)
  end

  defp readable_in_any?(states, user_id, type, id) do
    Enum.any?(states, fn {entry, _index} -> Model.readable?(entry.state, user_id, type, id) end)
  end

  # A pair carries no values, only the row it's filed under, which the session holds - so that row is
  # judged as a named row is. A row's values pin the state they came from, bounded by its place.
  defp leak(record, indexed, user_id) do
    candidates = candidates(record, indexed)
    open = open_candidates(record, indexed)

    row_explained? =
      if Map.get(record, :pair?, false),
        do: readable_in_any?(open, user_id, record.type, record.id),
        else: Enum.any?(candidates, fn {entry, _index} -> explains?(entry, record, user_id) end)

    if row_explained? and named_readable?(open, user_id, record) do
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
