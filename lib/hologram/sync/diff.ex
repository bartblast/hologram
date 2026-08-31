defmodule Hologram.Sync.Diff do
  @moduledoc false

  # Turns a round into what one client is told: which rows it did not have, which of the rows it
  # has changed, and which it no longer has. The round itself is shared by every client of the
  # window - what differs between them is what they may see and what they were told last, and
  # both of those live here rather than in the query.

  alias Hologram.Auth
  alias Hologram.Entity.NotIncluded

  @doc """
  Returns what changed for a client between the ids it holds and the round it is being told
  about: the rows that appeared, the rows whose values moved, and the ids that went away.

  A round's rows are the window's roots and every row embedded under them, and each of those is
  a member in its own right: a row reached only through an include appears, is patched, and
  vanishes the way a root does, because what a client holds is a flat set of entities rather
  than a tree.

  Visibility is decided per row, per client, against the round's rows - embedded rows included -
  which is what lets one query answer a hundred clients who may each see a different part of it.
  What goes out is scrubbed to match: an unreadable member loses its slot in every embedded
  to-many list along with its own deltas, so no id list ever names a row the client was not
  given.

  Which values moved comes from the effects, which name the attributes a transaction touched -
  but every value comes from the round's rows, never from the effects themselves. Effects arrive
  in an order that is stable rather than the order things committed, so a value read from one
  could be an older value than the row already holds. Effects naming rows the client does not
  hold, or attributes the row does not have, are passed over: the first is what the appeared and
  vanished lists are for, the second is what a peer running a newer model writes.

  Edges of to-many relationships are reported the way values are: the effects name which edge to
  look at, and whether it is there now is read from the round. An edge is only reported for a row
  the client can see, and only for a relationship the window embeds - a window that never carried
  those edges has nothing to say about them. An ADDED edge is reported only for a target the client
  is also being given, since it names that row the way an embedded list does. A REMOVED one names a
  row the round does not hold, which is what removing it means, so it is never measured against
  what the round makes visible. Each carries the type of the row the relationship lives on, which
  is what names it on the wire.

  Vanishing is reported per window. Whether the client is told to drop the row depends on the
  rest of what it holds, which only the session knows.
  """
  @spec deltas(
          %{ids: MapSet.t(), rows: map},
          MapSet.t(),
          String.t() | nil,
          list({term, list(map)})
        ) ::
          %{
            appeared: list(struct),
            edges: list(map),
            patched: list({struct, map}),
            vanished: list(String.t())
          }
  def deltas(result, held_ids, actor_user_id, transactions) do
    visible =
      result.rows
      |> members()
      |> Map.filter(fn {_id, row} -> Auth.can?(actor_user_id, :read, row) end)

    visible_ids =
      visible
      |> Map.keys()
      |> MapSet.new()

    appeared_ids = MapSet.difference(visible_ids, held_ids)
    held_visible_ids = MapSet.intersection(visible_ids, held_ids)

    appeared =
      appeared_ids
      |> Enum.map(&Map.fetch!(visible, &1))
      |> Enum.map(&scrub(&1, visible_ids))

    patched =
      visible
      |> patched(held_visible_ids, changed_attributes(transactions))
      |> Enum.map(fn {row, patch} -> {scrub(row, visible_ids), patch} end)

    %{
      appeared: appeared,
      edges: edges(visible, visible_ids, transactions),
      patched: patched,
      vanished: vanished(held_ids, visible_ids)
    }
  end

  @doc """
  Returns what a returning client's rows look like judged twice - under the grants it holds now,
  and under the ones given as `grants_then` - as the rows that appeared between the two and the
  rows that vanished.

  A grant given or taken away while a client was gone moves one row and changes what it may see
  of many, none of which the log names. So the rows are judged again rather than looked up: what
  the old grants admitted and the current ones do not is no longer the client's to hold, and what
  the current ones admit and the old ones did not was never sent.

  Visibility is per row and per client here exactly as it is in `deltas/4`, embedded rows
  included - a row reached only through an include appears and vanishes the way a root does.
  What appears is scrubbed against what the client may see NOW, so no id list names a row it was
  not given.
  """
  @spec shift(%{ids: MapSet.t(), rows: map}, String.t() | nil, list(struct)) ::
          %{appeared: list(struct), vanished: list(struct)}
  def shift(result, actor_user_id, grants_then) do
    members = members(result.rows)

    visible_now = Map.filter(members, fn {_id, row} -> Auth.can?(actor_user_id, :read, row) end)

    visible_then =
      Map.filter(members, fn {_id, row} ->
        Auth.can?(actor_user_id, :read, row, grants_then)
      end)

    now_ids = member_ids(visible_now)
    then_ids = member_ids(visible_then)

    # Scrubbed on the same terms `deltas/4` scrubs an appearing row, and untestable here as long
    # as no fixture gates a type that embeds a to-many: the only such parent is readable by
    # everyone, so it is visible under both sets and never appears. Kept because the case is
    # real - a client granted a parent while it was away receives it - not because a test binds it.
    appeared =
      now_ids
      |> MapSet.difference(then_ids)
      |> Enum.map(&Map.fetch!(visible_now, &1))
      |> Enum.map(&scrub(&1, now_ids))

    vanished =
      then_ids
      |> MapSet.difference(now_ids)
      |> Enum.map(&Map.fetch!(visible_then, &1))

    %{appeared: appeared, vanished: vanished}
  end

  defp attribute_names(nil), do: MapSet.new()

  defp attribute_names(data) do
    data
    |> Map.keys()
    |> MapSet.new()
  end

  defp changed_attributes(transactions) do
    transactions
    |> Enum.flat_map(fn {_tx, events} -> events end)
    |> Enum.filter(&(&1.op in [:patch_entity, :put_entity]))
    |> Enum.reduce(%{}, fn event, changed ->
      names = attribute_names(event.data)

      Map.update(changed, event.entity_id, names, &MapSet.union(&1, names))
    end)
  end

  defp collect(row, members) do
    if Map.has_key?(members, row.id) do
      members
    else
      row.__struct__.__relationships__()
      |> Enum.flat_map(fn {name, _target, _opts} -> embedded_rows(Map.fetch!(row, name)) end)
      |> Enum.reduce(Map.put(members, row.id, row), &collect/2)
    end
  end

  defp edge(event, visible) do
    with %{"relationship" => name, "target_id" => target_id} <- event.data,
         %{} = row <- Map.get(visible, event.entity_id),
         targets when is_list(targets) <- embedded(row, name) do
      op = edge_op(targets, target_id)

      [
        %{
          entity_id: event.entity_id,
          op: op,
          relationship: name,
          target_id: target_id,
          type: row.__struct__
        }
      ]
    else
      _no_edge_to_report -> []
    end
  end

  defp edge_op(targets, target_id) do
    if Enum.any?(targets, &(&1.id == target_id)) do
      :add_relationship
    else
      :del_relationship
    end
  end

  defp edges(visible, visible_ids, transactions) do
    transactions
    |> Enum.flat_map(fn {_tx, events} -> events end)
    |> Enum.filter(&(&1.op in [:add_relationship, :del_relationship]))
    |> Enum.flat_map(&edge(&1, visible))
    |> Enum.reject(&hidden_target?(&1, visible_ids))
    |> Enum.uniq()
  end

  # What the round says the relationship holds now, or nothing when the window does not embed it -
  # a relationship it never carried leaves a sentinel here rather than a list of rows.
  defp embedded(row, name) do
    row
    |> Map.from_struct()
    |> Enum.find_value(fn {field, value} -> Atom.to_string(field) == name && value end)
  end

  defp embedded_rows(%NotIncluded{}), do: []

  defp embedded_rows(nil), do: []

  defp embedded_rows(rows) when is_list(rows), do: rows

  defp embedded_rows(row), do: [row]

  # An added edge names its target the way an embedded list does, so it is withheld on the same
  # terms - a client is never told about a row it is not being given. A removed one is not measured
  # against what the round makes visible at all: the round no longer holds that row, which is what
  # removing it means, so absence there says nothing about who may read it.
  defp hidden_target?(%{op: :add_relationship, target_id: target_id}, visible_ids) do
    not MapSet.member?(visible_ids, target_id)
  end

  defp hidden_target?(_edge, _visible_ids), do: false

  # Every row a round carries, keyed by id: the roots and every row embedded under them, however
  # deep. One id can arrive in more than one place, and the first copy found keeps the spot - every
  # copy was read by the same query in the same round, so they hold the same values.
  defp member_ids(members) do
    members
    |> Map.keys()
    |> MapSet.new()
  end

  defp members(rows) do
    Enum.reduce(rows, %{}, fn {_id, row}, members -> collect(row, members) end)
  end

  # Names arrive as they were written rather than as atoms, so they are matched against the row's
  # own fields - which never invents an atom for something this node has never compiled.
  defp patch(row, names) do
    row
    |> Map.from_struct()
    |> Map.filter(fn {field, _value} -> Atom.to_string(field) in names end)
  end

  defp patched(visible, held_visible_ids, changed) do
    held_visible_ids
    |> Enum.map(fn id -> {Map.fetch!(visible, id), Map.get(changed, id, MapSet.new())} end)
    |> Enum.map(fn {row, names} -> {row, patch(row, names)} end)
    |> Enum.reject(fn {_row, patch} -> patch == %{} end)
  end

  # What leaves here is what this client may see, embedded lists included: an unreadable member
  # loses its slot in every to-many list, however deep, not only its own deltas. To-one embeds
  # stay as they are - the wire never spells them (the reference field carries the id), so there
  # is nothing to hide. Scrubbing at the source rather than at the spelling covers every path a
  # row takes out, the catch-up store included.
  defp scrub(row, visible_ids) do
    updates =
      for {name, _target, _opts} <- row.__struct__.__relationships__(),
          targets = Map.fetch!(row, name),
          is_list(targets) do
        {name, scrub_targets(targets, visible_ids)}
      end

    struct(row, updates)
  end

  defp scrub_targets(targets, visible_ids) do
    targets
    |> Enum.filter(&MapSet.member?(visible_ids, &1.id))
    |> Enum.map(&scrub(&1, visible_ids))
  end

  defp vanished(held_ids, visible_ids) do
    held_ids
    |> MapSet.difference(visible_ids)
    |> MapSet.to_list()
  end
end
