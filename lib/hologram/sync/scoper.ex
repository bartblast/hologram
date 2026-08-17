defmodule Hologram.Sync.Scoper do
  @moduledoc false

  # Decides which registered windows a batch of effects can have changed the answer of, so that
  # only those are run again. Deciding wrongly in favour of running is slower than it needed to
  # be - deciding wrongly against it leaves a client holding an answer that is no longer true, so
  # every rule here errs towards including.

  alias Hologram.Auth.RoleGrant

  @grant_edges [:global_grants, :own_grants, :relationship_grants, :resource_grants, :type_grants]

  @doc """
  Returns the keys of the windows a batch of transactions can have changed.

  Windows are given as `{key, term}` pairs and the keys come back as they went in - what a key
  identifies is the caller's business. Edges are the policy dependency index, passed in rather
  than derived here, so a caller reading it once can hand it to every batch.

  A window depends on the entity types its query reads, its own and through everything it
  includes, and on the types its policies consult to decide who sees those rows: the grant store,
  for any rule granting by role, and a related type whose attributes a delegated rule reads.

  Attribute names on the edges are deliberately not used to narrow further. A query result is
  whole entities, so a client holding a row wants any change to it - which makes an attribute
  change on a type the query reads always worth a run, whichever attribute moved.

  The universal edges - an auth change and a deploy - are not decided here: no effect in the log
  says either of those happened. A session learns of the first from its own identity changing,
  and of the second from the model hash it was greeted with.
  """
  @spec affected(list({non_neg_integer, list(map)}), list({any, map}), %{
          {module, atom} => list(tuple)
        }) :: list(any)
  def affected(transactions, windows, edges) do
    changed = changed_types(transactions)

    for {key, term} <- windows,
        not MapSet.disjoint?(changed, dependencies(term, edges)),
        do: key
  end

  defp add_edge_types({:attributes, _names}, types), do: types

  defp add_edge_types({:relationship_attributes, _chain, entity_type, _names}, types) do
    MapSet.put(types, entity_type)
  end

  defp add_edge_types(edge, types) when elem(edge, 0) in @grant_edges do
    MapSet.put(types, RoleGrant)
  end

  defp changed_types(transactions) do
    transactions
    |> Enum.flat_map(fn {_tx, events} -> events end)
    |> MapSet.new(& &1.type)
  end

  defp dependencies(term, edges) do
    read_types = read_types(term, MapSet.new())

    Enum.reduce(read_types, read_types, fn entity_type, types ->
      edges
      |> Map.get({entity_type, :read}, [])
      |> Enum.reduce(types, &add_edge_types/2)
    end)
  end

  defp read_types(term, types) do
    term.include
    |> Map.values()
    |> Enum.reduce(MapSet.put(types, term.entity), &read_types/2)
  end
end
