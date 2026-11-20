defmodule Hologram.Component.Derived.QueryCheck do
  @moduledoc false

  # What a derived field's query must not ask for. A derived field's query is read for the session
  # user on the server and answered again in the browser from the rows the browser holds, so it can
  # neither read a type no rule lets anyone read, nor name an attribute the browser never holds, nor
  # claim the server's authority.
  #
  # WARNING: server_only_refusal/1 must match the client's QueryCheck (query_check.mjs), messages
  # included. The client checks nothing else: its trust/1 refuses a claim of trust itself, and a type
  # no rule lets anyone read is refused on the server's render only, since a deploy changing only the
  # rules can leave an open tab's type with none, and that tab answers from the rows it holds rather
  # than failing its render.

  alias Hologram.Entity
  alias Hologram.Entity.Derived
  alias Hologram.Policy
  alias Hologram.Query
  alias Hologram.Query.Stage

  @doc """
  Returns why the given normalized query term can't be a derived field's query, as the rest of a
  sentence about it, or nil when it can. The first refusal is returned, in the order
  `dead_refusal/1`, `server_only_refusal/1`, `trust_refusal/1` check them.
  """
  @spec refusal(Query.t()) :: String.t() | nil
  def refusal(term) do
    dead_refusal(term) || server_only_refusal(term) || trust_refusal(term)
  end

  @doc """
  Returns why the given normalized query term reads nothing, as the rest of a sentence about it, or
  nil when it may read rows: a type with no allow lines is read by no session, default deny
  composing into every statement the read reaches. The root, an include target and a type a path
  goes through fail differently, so they are told apart - and a dead root is told alone, because a
  query returning no rows has no embeds to be empty either.
  """
  @spec dead_refusal(Query.t()) :: String.t() | nil
  def dead_refusal(term) do
    case Policy.dead_entity_types([term.entity]) do
      [] ->
        dead_include_refusal(term) || dead_path_refusal(term)

      dead_entity_types ->
        "reads #{listing(dead_entity_types)}, which #{declare_verb(dead_entity_types)} no allow lines - default deny returns no rows to any session. Add allow lines, or drop the query."
    end
  end

  @doc """
  Returns why the given normalized query term can't be answered in the browser, as the rest of a
  sentence about it, or nil when it can: its filter or sort names an attribute declared
  server_only, whose value the browser never holds.
  """
  @spec server_only_refusal(Query.t()) :: String.t() | nil
  def server_only_refusal(term) do
    case server_only_references(term) do
      [] ->
        nil

      references ->
        "filters or sorts on server_only attributes (#{server_only_listing(references)}) - the client never holds those values, so it could not evaluate the reference locally. Drop the reference, or read the rows through the trusted backend API."
    end
  end

  @doc """
  Returns why the given normalized query term claims an authority a derived field has none of, as
  the rest of a sentence about it, or nil when it claims none.
  """
  @spec trust_refusal(Query.t()) :: String.t() | nil
  def trust_refusal(term) do
    if term.trust do
      "claims the server's authority with trust() - a component's query is read for the session user on both tiers, so it cannot claim another. Drop trust(), or read through the backend API in a command."
    end
  end

  defp dead_include_refusal(term) do
    dead_entity_types =
      term
      |> included_entity_types()
      |> Policy.dead_entity_types()

    if dead_entity_types != [] do
      "includes #{listing(dead_entity_types)}, which #{declare_verb(dead_entity_types)} no allow lines - default deny leaves the embed empty in every row. Add allow lines, or drop the include."
    end
  end

  # A path through a type with no allow lines reads nothing on it: the policied read applies the
  # hop type's read policy, so every such hop is missing for every session.
  defp dead_path_refusal(term) do
    dead_entity_types =
      term
      |> path_entity_types()
      |> Policy.dead_entity_types()

    if dead_entity_types != [] do
      "filters through #{listing(dead_entity_types)}, which #{declare_verb(dead_entity_types)} no allow lines - default deny reads every such row as missing. Add allow lines, or drop the path."
    end
  end

  defp declare_verb([_single_entity_type]), do: "declares"

  defp declare_verb(_entity_types), do: "declare"

  # A derived field holding a value includes no rows, so it names no type.
  defp included_entity_types(term) do
    term
    |> sub_terms()
    |> Enum.flat_map(&queried_entity_types/1)
    |> Enum.uniq()
  end

  defp listing(entity_types) do
    Enum.map_join(entity_types, ", ", &inspect/1)
  end

  # The types a term's paths and quantifiers lead through, its includes' included: every type a hop
  # or a quantifier's set reaches - a derived set's rows among them - which a policied read applies
  # the read policy of.
  defp path_entity_types(term) do
    hop_types =
      term.filter
      |> Stage.relationship_chains()
      |> Enum.flat_map(fn relationship_names ->
        Enum.scan(relationship_names, term.entity, &Derived.related_type(&2, &1))
      end)

    term
    |> sub_terms()
    |> Enum.flat_map(&path_entity_types/1)
    |> Enum.concat(hop_types)
    |> Enum.uniq()
  end

  defp queried_entity_types(term) do
    nested_types =
      term
      |> sub_terms()
      |> Enum.flat_map(&queried_entity_types/1)

    Enum.uniq([term.entity | nested_types])
  end

  defp server_only_listing(references) do
    Enum.map_join(references, ", ", fn {entity_type, names} ->
      "#{inspect(entity_type)} #{Enum.map_join(names, ", ", &inspect/1)}"
    end)
  end

  # Pairs each entity type with the server-only attributes a term's filter and sort name on it -
  # the term's own type first, then the types its paths lead to - walking include sub-terms, whose
  # sets carry the order their relationship declares. A derived field's own reads are checked where
  # its definition is resolved.
  defp server_only_references(term) do
    filter_references =
      term.filter
      |> Stage.predicate_references()
      |> Enum.map(fn {relationship_names, name} ->
        {Derived.path_target(term.entity, relationship_names), name}
      end)

    sort_references =
      Enum.map(term.sort, fn {name, _direction} -> {term.entity, name} end)

    references_by_type =
      (filter_references ++ sort_references)
      |> Enum.filter(fn {entity_type, name} ->
        name in Entity.server_only_attribute_names(entity_type)
      end)
      |> Enum.group_by(fn {entity_type, _name} -> entity_type end, fn {_type, name} -> name end)

    {own_references, path_references} = Map.split(references_by_type, [term.entity])

    nested_references =
      term
      |> sub_terms()
      |> Enum.flat_map(&server_only_references/1)

    sorted_path_references =
      Enum.sort_by(path_references, fn {entity_type, _names} -> inspect(entity_type) end)

    own_references
    |> Enum.concat(sorted_path_references)
    |> Enum.map(fn {entity_type, names} -> {entity_type, sorted_unique(names)} end)
    |> Enum.concat(nested_references)
  end

  defp sorted_unique(names) do
    names
    |> Enum.uniq()
    |> Enum.sort()
  end

  # The terms a term includes, in name order so that what is reported doesn't depend on the map's
  # order. A derived field holding a value is included with nothing under it.
  defp sub_terms(term) do
    term.include
    |> Enum.sort()
    |> Enum.map(fn {_name, sub_term} -> sub_term end)
    |> Enum.reject(&is_nil/1)
  end
end
