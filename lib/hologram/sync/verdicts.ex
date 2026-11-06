defmodule Hologram.Sync.Verdicts do
  @moduledoc false

  # What a session has told its client of the server's verdicts, and which of them a round makes
  # out of date.
  #
  # A verdict is the server's answer on a policy condition a browser cannot decide over the rows it
  # holds (see Hologram.Auth.verdicts/2). Every row a client is put carries its verdicts, so a row
  # that arrives is current. A row the client already holds can have its verdicts move without the
  # row moving at all - a task deletable while its board has no cards stops being so the moment a
  # card is added - so the session keeps what it last told, and a round that touched a type a
  # verdict reads works the row's verdicts out again and tells only what changed.
  #
  # The bookkeeping is kept here, apart from the session that holds it, so what is told when can be
  # judged without a running window.

  alias Hologram.Policy
  alias Hologram.Sync.Frame

  @doc """
  Returns the given round's patches, `{row, changes}`, as a frame carries them -
  `{row, changes, verdicts}` - with the given stale verdicts, `{row, verdicts}`, riding them: the
  verdicts of a patched row beside its changes, nil for one whose verdicts did not move, and a patch
  naming no value for a row whose verdicts alone moved, in id order after the others.
  """
  @spec patches(list({struct, map}), list({struct, map})) :: list({struct, map, map | nil})
  def patches(patched, stale) do
    stale_by_id = Map.new(stale, fn {row, verdicts} -> {row.id, verdicts} end)
    patched_ids = MapSet.new(patched, fn {row, _changes} -> row.id end)

    with_verdicts =
      Enum.map(patched, fn {row, changes} -> {row, changes, Map.get(stale_by_id, row.id)} end)

    verdicts_only =
      stale
      |> Enum.reject(fn {row, _verdicts} -> MapSet.member?(patched_ids, row.id) end)
      |> Enum.sort_by(fn {row, _verdicts} -> row.id end)
      |> Enum.map(fn {row, verdicts} -> {row, %{}, verdicts} end)

    with_verdicts ++ verdicts_only
  end

  @doc """
  Returns the given told verdicts, `%{id => verdicts}`, with what the given outgoing deltas tell
  recorded: a put states a row's verdicts whole - none when it carries none - a patch carrying
  verdicts replaces them, and a row that left the client takes them with it.
  """
  @spec remember(%{String.t() => map}, list(map)) :: %{String.t() => map}
  def remember(told, deltas) do
    Enum.reduce(deltas, told, fn
      %{data: data, id: id, op: :put_entity}, acc ->
        case Map.get(data, :"$verdicts") do
          nil -> Map.delete(acc, id)
          verdicts -> Map.put(acc, id, verdicts)
        end

      %{data: %{"$verdicts": verdicts}, id: id, op: :patch_entity}, acc ->
        Map.put(acc, id, verdicts)

      %{id: id, op: :unsync_entity}, acc ->
        Map.delete(acc, id)

      _delta, acc ->
        acc
    end)
  end

  @doc """
  Returns the rows among the given ones whose verdicts for the given user differ from what was
  told, each with its verdicts now, in the order given.

  Only rows of a type with a deciding quantifier are worked out again: every one of them when the
  given changed types meet a type such a quantifier reads through a relationship (see
  `Hologram.Policy.verdict_related_reads/2`), and otherwise only the rows whose own values moved,
  among the given patched ids, since a quantifier may read the row it decides about. Given `:all`,
  every row of such a type is worked out - what a client resuming with verdicts it was told before
  this session is owed.
  """
  @spec stale(
          list(struct),
          %{String.t() => map},
          String.t() | nil,
          MapSet.t(module) | :all,
          MapSet.t(String.t())
        ) :: list({struct, map})
  def stale(rows, told, actor_user_id, changed_types, patched_ids \\ MapSet.new()) do
    worked_out =
      rows
      |> MapSet.new(& &1.__struct__)
      |> Map.new(&{&1, scope(&1, changed_types)})

    rows
    |> Enum.filter(fn row ->
      case Map.fetch!(worked_out, row.__struct__) do
        :every_row -> true
        :patched_rows -> MapSet.member?(patched_ids, row.id)
        :none -> false
      end
    end)
    |> Enum.map(&{&1, Frame.row_verdicts(actor_user_id, &1)})
    |> Enum.reject(fn {row, verdicts} -> verdicts == Map.get(told, row.id, %{}) end)
  end

  # Which rows of the type a round makes worth working out again.
  defp scope(entity_type, changed_types) do
    deciding = Policy.deciding_quantifiers(entity_type)

    cond do
      deciding == [] ->
        :none

      changed_types == :all ->
        :every_row

      Enum.any?(deciding, fn {_key, clause} ->
        entity_type
        |> Policy.verdict_related_reads(clause)
        |> Enum.any?(&MapSet.member?(changed_types, &1))
      end) ->
        :every_row

      true ->
        :patched_rows
    end
  end
end
