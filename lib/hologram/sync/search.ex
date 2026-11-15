defmodule Hologram.Sync.Search do
  @moduledoc false

  # The backwards search: from the rows a batch of effects changed to the rows whose read access the
  # change may have moved, without those rows changing themselves. A read rule points forward, from
  # the row it decides about to the rows it reads, and `Hologram.Policy.Edges` names what it reads.
  # The search follows those edges the other way.
  #
  # It runs after commit, against the tables as they now stand. Running it inside the write misses
  # rows: one transaction moves a milestone into a project while another adds a member to it, and
  # the member's search runs before the milestone's move is visible, while the move's search runs
  # before the member is. Read after both commit, either search finds the other's row. A link the
  # walk reads that changes after it ran is an effect of its own, in this batch or a later one, and
  # every link a chain is followed through is named by an edge - so its own search covers it.
  #
  # Each step back is one query on an indexed column, for all the ids that reached it at once, so
  # the cost follows the rows a change reaches rather than the size of the tables.

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity

  @whole_row_ops [:del_entity, :put_entity]

  @pair_ops [:add_relationship, :del_relationship]

  @known_ops [:patch_entity | @whole_row_ops ++ @pair_ops]

  @doc """
  Returns the rows whose read access the given effects may have moved, per entity type, and the
  users for whom every row of a type may have.

  Effects come as `Hologram.DB.Oplog.read_window/2` reads them, flattened: data and old references
  keyed by strings, as stored. A put, a patch or a delete without its data - the shape
  `read_after/3` returns them in - raises when a read edge leads to its type, since a search
  without the values a write left misses rows. An effect of an entity type or an op this node does
  not know is passed over, with or without data.

  Edges are the policy dependency index (see `Hologram.Policy.Edges.index/0`), passed in rather
  than read here. Only the read rules' edges are followed.

  The rows the effects wrote are not listed - they are rows to check whatever their rules read, and
  the caller has them. So a change to a column no read rule reads lists nothing. A listed row may
  be gone, which reading it again answers.
  """
  @spec candidates(list(map), %{{module, atom} => list(tuple)}) :: %{
          rows: %{module => MapSet.t(String.t())},
          whole_types: %{module => MapSet.t(String.t())}
        }
  def candidates(effects, edges) do
    triggers = triggers(edges)

    entries =
      Enum.flat_map(effects, fn effect ->
        triggers
        |> Map.get(effect.type, [])
        |> Enum.flat_map(fn {entity_type, edge} -> entries(effect, entity_type, edge) end)
      end)

    %{rows: walk_entries(entries, DB.mapping()), whole_types: %{}}
  end

  # An entry is a walk to run: ids at the end of a chain prefix, to be followed back to the rows of
  # the type the prefix starts from.
  defp entries(effect, entity_type, {:relationship_attributes, chain, _target_type, names}) do
    if touches?(effect, names) do
      [{entity_type, chain, [effect.entity_id]}]
    else
      []
    end
  end

  # The types a chain passes through, each with the relationship followed from it - in walking
  # order, from the type the chain starts at.
  defp link_owners(entity_type, chain) do
    {owners, _last_type} =
      Enum.map_reduce(chain, entity_type, fn link, owner_type ->
        {{owner_type, link}, Entity.related_type(owner_type, link)}
      end)

    owners
  end

  defp qualified_table(table) do
    "#{Mapper.quote_identifier(Mapper.data_schema())}.#{Mapper.quote_identifier(table)}"
  end

  defp reference_column(mapping, entity_type, link) do
    mapping
    |> Map.fetch!(entity_type)
    |> Map.fetch!(:columns)
    |> Enum.find(&(&1.source == {:relationship, link}))
    |> Map.fetch!(:name)
  end

  defp select_ids(statement, ids) do
    params = [Enum.map(ids, &Codec.encode(&1, :uuid))]

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, params)

    for [id] <- rows, id != nil, into: MapSet.new(), do: Codec.decode(id, :uuid)
  end

  # One step back along a chain: from the rows a link leads to, to the rows it is followed from.
  # A step reached by no ids asks nothing.
  defp step(mapping, owner_type, link, ids) do
    if MapSet.size(ids) == 0 do
      ids
    else
      select_ids(step_statement(mapping, owner_type, link), MapSet.to_list(ids))
    end
  end

  # A stored to-one: the rows whose reference column holds one of the ids.
  # sobelow_skip ["SQL.Query"]
  defp step_statement(mapping, owner_type, link) do
    %{table: table} = Map.fetch!(mapping, owner_type)

    column =
      mapping
      |> reference_column(owner_type, link)
      |> Mapper.quote_identifier()

    ~s|SELECT "id" FROM #{qualified_table(table)} WHERE #{column} = ANY($1::uuid[])|
  end

  # A put says what a row became and a delete what it was, every column of it, so they touch every
  # name. A patch touches the columns it wrote. Names are matched as the log spells them, so nothing
  # read from it becomes an atom.
  defp touches?(%{op: op, data: data}, _names) when op in @whole_row_ops and is_map(data),
    do: true

  defp touches?(%{op: :patch_entity, data: data}, names) when is_map(data) do
    Enum.any?(names, &Map.has_key?(data, Atom.to_string(&1)))
  end

  defp touches?(%{op: op, data: data}, _names) when op in @pair_ops and is_map(data), do: false

  # An op a newer peer wrote stays the label it was written with, or becomes an atom this node
  # happens to know for something else - either way it moved nothing this build can follow.
  defp touches?(%{op: op}, _names) when op not in @known_ops, do: false

  defp trigger_type({:relationship_attributes, _chain, target_type, _names}), do: target_type

  defp trigger_type(_edge), do: nil

  # The read edges, keyed by the entity type whose effects can start a walk along them.
  defp triggers(edges) do
    edges
    |> Enum.flat_map(fn
      {{entity_type, :read}, read_edges} -> Enum.map(read_edges, &{entity_type, &1})
      {_pair, _edges} -> []
    end)
    |> Enum.flat_map(fn {entity_type, edge} ->
      case trigger_type(edge) do
        nil -> []
        trigger_type -> [{trigger_type, {entity_type, edge}}]
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp walk(mapping, entity_type, chain, ids) do
    entity_type
    |> link_owners(chain)
    |> Enum.reverse()
    |> Enum.reduce(ids, fn {owner_type, link}, step_ids ->
      step(mapping, owner_type, link, step_ids)
    end)
  end

  # Entries sharing a type and a chain walk once, for all their ids together.
  defp walk_entries(entries, mapping) do
    entries
    |> Enum.group_by(fn {entity_type, chain, _ids} -> {entity_type, chain} end, &elem(&1, 2))
    |> Enum.reduce(%{}, fn {{entity_type, chain}, id_lists}, rows ->
      ids =
        id_lists
        |> List.flatten()
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      reached = walk(mapping, entity_type, chain, ids)

      if MapSet.size(reached) == 0 do
        rows
      else
        Map.update(rows, entity_type, reached, &MapSet.union(&1, reached))
      end
    end)
  end
end
