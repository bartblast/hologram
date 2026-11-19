defmodule Hologram.Sync.Verdicts do
  @moduledoc false

  # What a session has told its client of the server's verdicts, and which of them a batch makes
  # out of date.
  #
  # A verdict is the server's answer on a policy condition a browser cannot decide over the rows it
  # holds (see Hologram.Auth.verdicts/2). Every row a client is put carries its verdicts, so a row
  # that arrives is current. A row the client already holds can have its verdicts move without the
  # row moving at all - a task deletable while its board has no cards stops being so the moment a
  # card is added - so the session keeps what it last told, and tells only what changed: of the
  # verdicts a batch's recheck read for the rows it may have moved them of (see
  # `Hologram.Sync.Live.parts/5`), and of the ones worked out for a returning client's rows.
  #
  # The bookkeeping is kept here, apart from the session that holds it, so what is told when can be
  # judged without a running session.

  alias Hologram.Policy
  alias Hologram.Sync.Frame

  @doc """
  Returns the given rows' verdicts, `{row, verdicts}`, that differ from what was told, in the order
  given - for verdicts already worked out, as a batch's recheck works them out (see
  `Hologram.Sync.Live.parts/5`).
  """
  @spec moved(list({struct, map}), %{String.t() => map}) :: list({struct, map})
  def moved(row_verdicts, told) do
    Enum.reject(row_verdicts, fn {row, verdicts} -> verdicts == Map.get(told, row.id, %{}) end)
  end

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
  told, each with its verdicts now, in the order given. Only rows of a type with a deciding
  quantifier are worked out: a row of any other type is left out, whatever was told of it, so a
  caller can't rely on this to clear verdicts told before - and a session has none of it to clear:
  such a row is put with none (see `Hologram.Sync.Frame.row_verdicts/2`), and no rule reads any a
  client holds of it from an earlier build.

  For the rows a returning client may hold verdicts of from before this session - a batch's rows
  come with theirs worked out (see `moved/2`).
  """
  @spec stale(list(struct), %{String.t() => map}, Hologram.Server.identity_id() | nil) ::
          list({struct, map})
  def stale(rows, told, actor_user_id) do
    rows
    |> Enum.filter(&(Policy.deciding_quantifiers(&1.__struct__) != []))
    |> Enum.map(&{&1, Frame.row_verdicts(actor_user_id, &1)})
    |> moved(told)
  end
end
