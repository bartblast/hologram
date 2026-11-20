defmodule Hologram.Query.Window do
  @moduledoc false

  alias Hologram.Entity
  alias Hologram.Entity.Derived
  alias Hologram.Policy
  alias Hologram.Query
  alias Hologram.Query.Stage

  @quantifiers [:all, :any, :none]

  # The rows a query reads beside the ones it returns, as includes: what the server renders a
  # query with, so the rows a path, a quantifier, a derived field or a rule reads arrive with the
  # ones it returns, and the types it reads, which sync has to send (see entity_types/1).
  #
  # A PATH reads rows the query does not return, so every path the filter names - on either side
  # of a comparison, inside alternatives - has its relationships embedded as to-one includes,
  # merged with the query's own.
  #
  # A QUANTIFIER reads the rows of a related set, so every set a quantifier reads - nested ones and
  # the rows along its source included - is embedded as an include, the rows its condition's paths
  # read with it. A set read off its rows' own reference field is narrowed by the quantifier's
  # condition: `any` and `none` are decided by the related rows the condition matches, so only
  # those are embedded. `all` is decided by the rows the condition does NOT match, so its set is
  # embedded whole, and so is a set read through the ids filed for its row - a to-many, or an
  # inverse of one - since a row states the whole set it names. A set before the last link of a
  # source is embedded whole too, since every row of it leads to related rows. Two narrowings of
  # one set are joined with `or`, and a whole one wins.
  #
  # A narrowing keeps only what bounds the rows for every reader, whatever rows it may read:
  #
  # - A path predicate that matches a missing related row - `channel.archived != true`,
  #   `channel.name == nil`, a membership holding nil, an equality with another attribute - bounds
  #   nothing: a reader who may not read the related row reads it as missing. It is dropped.
  # - A DISJUNCTION narrows each alternative to what bounds it, and is dropped whole when an
  #   alternative loses every predicate, since that alternative admits every row. Dropping a
  #   conjunct widens what arrives, which is safe; dropping an alternative would narrow it.
  # - A nested `any` stays, narrowed by the same rules: a reader holding fewer related rows makes
  #   it false more often, never true. A nested `none` or `all` is dropped, since a reader holding
  #   fewer related rows can make it true where the stored rows make it false.
  # - A part reading a row above the set bounds nothing about the set's own rows, and is left out.
  #
  # A DERIVED FIELD is computed from the rows its definition reads, so those are embedded where the
  # field is read: under the relationships its sources go through, narrowed by its definition's
  # literal conditions as a quantifier's set is.
  #
  # A client that checks permissions answers each rule over the rows it holds, and a rule can read
  # rows other than the one it decides about - the row a `via:` leads to, the rows before the last
  # relationship of a `to:` reference, the rows along a `when:` path, the sets a quantifier reads.
  # So when the build has a page checking permissions on the client, the chains the rules of the
  # type a query returns read (see `Hologram.Policy.related_chains/1`) are embedded whole, the way
  # a path's relationships are, and so are those of every type it includes, under that include. A
  # chain stops before its first type no session may read (see
  # `Hologram.Policy.readable_prefix/2`): no client is ever sent such a row. A row embedded for a
  # path or for a rule gets no rule chains of its own: whatever a delegation reads through it is in
  # the delegating type's chains already, and a rule reading a row of its own type would otherwise
  # never stop embedding.

  @doc """
  Returns the given query term with the rows it reads beside the ones it returns embedded as
  includes, merged with its own, the sub-terms of its includes embedded the same way: the
  relationships its paths go through, the sets its quantifiers read, the rows the derived fields it
  reads are computed from and, when the build has a page checking permissions on the client, the
  chains the rules of the types it returns and includes read (see the module's comment for how
  each is narrowed).

  The term's own clauses stay as written - it answers the query as authored. An authored include
  of a set a quantifier reads, whole, is left as authored.

  A term with nothing to embed comes back unchanged.
  """
  @spec embed(Query.t(), boolean) :: Query.t()
  def embed(term, permission_checking?) do
    # A derived field's rows are computed from the sources embedded beside them, so nothing is
    # embedded under them - no client reads it.
    authored_include =
      Map.new(term.include, fn {name, sub_term} ->
        if sub_term == nil or Derived.declared?(term.entity, name) do
          {name, sub_term}
        else
          {name, embed(sub_term, permission_checking?)}
        end
      end)

    embedded_include = put_embedded_includes(%{}, term, permission_checking?)

    %{term | include: merged_includes(authored_include, embedded_include)}
  end

  @doc """
  Returns the entity types the given normalized query term reads, sorted: its own, every one it
  includes, every one a path in its filter goes through, every one a quantifier's set goes through
  and every one a derived field it reads is computed from - the types of the rows the client
  answers it over, which it holds every row of only once each of them is complete.
  """
  @spec entity_types(Query.t()) :: [module]
  def entity_types(term) do
    term
    |> embed(false)
    |> collect_entity_types(MapSet.new())
    |> Enum.sort()
  end

  # A derived field holding a value is included as nil - the rows it is computed from are embedded
  # beside it, under their relationships, and read there.
  defp collect_entity_types(term, acc) do
    path_types =
      term.filter
      |> Stage.relationship_chains()
      |> Enum.flat_map(fn relationship_names ->
        Enum.scan(relationship_names, term.entity, &Derived.related_type(&2, &1))
      end)

    own_types =
      acc
      |> MapSet.put(term.entity)
      |> MapSet.union(MapSet.new(path_types))

    term.include
    |> Map.values()
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(own_types, &collect_entity_types/2)
  end

  # A narrowing's clause lists as alternatives - the ones of the disjunction it already is, or itself.
  defp alternatives([{:or, alternatives}]), do: alternatives

  defp alternatives(clauses), do: [clauses]

  # The derived fields the given clauses read, as {chain, name} pairs - the chain of relationships
  # from the root row to the row declaring the field: a name compared, an operand, a path's end, and
  # a set a quantifier's source ends at. The prefixes resolve the clauses as Stage does.
  defp clause_derived_reads(clauses, root, prefixes) do
    name_reads =
      clauses
      |> Stage.predicate_references(prefixes)
      |> Enum.filter(fn {relationships, name} -> derived_at?(root, relationships, name) end)

    source_reads =
      clauses
      |> Stage.relationship_chains(prefixes)
      |> Enum.filter(&derived_end?(root, &1))
      |> Enum.map(fn chain ->
        {owner_chain, [name]} = Enum.split(chain, -1)

        {owner_chain, name}
      end)

    Enum.uniq(name_reads ++ source_reads)
  end

  # What a derived field's query narrows its embedded set by: its conditions about the set's
  # rows alone - none reading the owning row, which says nothing at build time - and only for a set
  # read off its rows' own reference field, as a quantifier's set is narrowed.
  defp definition_narrowing(term, root, set_chain, owner_chain) do
    {set_owner_chain, [set_name]} = Enum.split(set_chain, -1)
    set_owner_type = Entity.path_target(root, set_owner_chain)
    scope = [term.entity, Entity.path_target(root, owner_chain)]

    with %{reference?: true} <- Entity.inverse_relationship(set_owner_type, set_name),
         [_clause | _clauses] = narrowing <-
           term.filter
           |> narrowed_clauses(scope)
           |> Enum.filter(&self_contained?(&1, 0))
           |> Stage.normalized_filter() do
      narrowing
    else
      _whole -> nil
    end
  end

  # Whether the name is a derived field of the row the relationships lead to.
  defp derived_at?(entity_type, relationship_names, name) do
    entity_type
    |> Derived.path_target(relationship_names)
    |> Derived.declared?(name)
  end

  defp derived_end?(_entity_type, []), do: false

  defp derived_end?(entity_type, chain) do
    {owner_chain, [name]} = Enum.split(chain, -1)

    derived_at?(entity_type, owner_chain, name)
  end

  defp derived_name?(nil, _scope), do: false

  defp derived_name?({:outer, levels, name}, scope),
    do: derived_name?(name, [Enum.at(scope, levels)])

  defp derived_name?(name, [entity_type | _rows_above]) do
    {relationship_names, [last_name]} =
      name
      |> List.wrap()
      |> Enum.split(-1)

    derived_at?(entity_type, relationship_names, last_name)
  end

  # Narrowings of one set download what any of them needs: one disjunction of their clause lists,
  # each list once, flattened from a disjunction they already form. A whole set - nil, or an empty
  # filter such as an authored include's - needs everything.
  defp joined_narrowing(narrowings) do
    if Enum.any?(narrowings, &(&1 in [nil, []])) do
      nil
    else
      joined_alternatives =
        narrowings
        |> Enum.flat_map(&alternatives/1)
        |> Enum.map(&Stage.normalized_filter/1)
        |> Enum.uniq()

      case joined_alternatives do
        [clauses] -> clauses
        several -> Stage.normalized_filter([{:or, several}])
      end
    end
  end

  # The sets before the last link of a quantifier's own source, each downloaded whole: every row of
  # one leads to related rows, so none narrows it - a set the source starts inside, a nested
  # quantifier's parent set, keeps its own narrowing.
  defp linked_sets(entity_type, chain, source) do
    hops =
      case source do
        {:outer, _levels, hops} -> hops
        hops -> hops
      end

    start_length = length(chain) - length(hops)

    (start_length + 1)..(length(chain) - 1)//1
    |> Enum.map(&Enum.take(chain, &1))
    |> Enum.filter(fn link_chain ->
      {owner_chain, [name]} = Enum.split(link_chain, -1)

      set_hop?(Derived.path_target(entity_type, owner_chain), name)
    end)
    |> Enum.flat_map(&mapped_chains(entity_type, &1))
    |> Enum.uniq()
    |> Enum.map(&{&1, nil})
  end

  # A chain read through the rows derived fields hold, as the chains to the rows they are computed
  # from - the chains embedded. A field choosing its rows with if holds the rows of every
  # query its branches name, so a chain through it maps onto each, and onto none for a field
  # holding none.
  defp mapped_chains(_entity_type, []), do: [[]]

  defp mapped_chains(entity_type, [name | later_names]) do
    if Derived.declared?(entity_type, name) do
      target_type = Derived.related_type(entity_type, name)

      for source_chain <- row_sources(Derived.definition(entity_type, name)),
          mapped_source <- mapped_chains(entity_type, source_chain),
          mapped_later <- mapped_chains(target_type, later_names),
          uniq: true,
          do: mapped_source ++ mapped_later
    else
      for mapped_later <- mapped_chains(Entity.related_type(entity_type, name), later_names),
          do: [name | mapped_later]
    end
  end

  # A render's authored includes as written, beside what it embeds - an authored include of an
  # embedded relationship stays whole, in its declared order, and gains what the embedded one
  # includes.
  defp merged_includes(authored_include, embedded_include) do
    Map.merge(embedded_include, authored_include, fn
      _name, _embedded_sub_term, nil ->
        nil

      _name, embedded_sub_term, authored_sub_term ->
        nested = merged_includes(authored_sub_term.include, embedded_sub_term.include)

        %{authored_sub_term | include: nested}
    end)
  end

  # A predicate reading a path that a reader's missing related row - nil - can satisfy.
  defp missing_path_match?({name, operator, operand}) do
    reads_path? = path_name?(name) or path_name?(operand_name(operand))

    reads_path? and nil_matching?(operator, operand)
  end

  defp nil_matching?(operator, {:attribute, _name}) when operator in [:==, :!=], do: true

  defp nil_matching?(:==, operand), do: is_nil(operand)

  defp nil_matching?(:!=, operand), do: not is_nil(operand)

  defp nil_matching?(:in, values) when is_list(values), do: nil in values

  defp nil_matching?(:not_in, values) when is_list(values), do: nil not in values

  defp nil_matching?(_operator, _operand), do: false

  defp operand_name({:attribute, name}), do: name

  defp operand_name(_operand), do: nil

  defp path_name?({:outer, _levels, name}), do: path_name?(name)

  defp path_name?([_hop, _name | _rest]), do: true

  defp path_name?(_name), do: false

  # What clauses read beside the rows they are about, embedded from the root row: the derived
  # fields they read, the sets their quantifiers read and the rows along their paths.
  defp put_clause_reads(include, root, prefixes, clauses, permission_checking?) do
    sets = quantified_sets(clauses, root, prefixes)

    chains =
      clauses
      |> Stage.relationship_chains(prefixes)
      |> Enum.flat_map(&mapped_chains(root, &1))

    include
    |> put_derived_reads(
      root,
      clause_derived_reads(clauses, root, prefixes),
      permission_checking?
    )
    |> then(&put_sets(sets, &1, root, permission_checking?))
    |> then(&Enum.reduce(chains, &1, fn chain, acc -> put_path_include(acc, root, chain) end))
  end

  # The rows the derived field of the given name, declared on the row the chain leads to, is
  # computed from, embedded under that row - recursively for the derived fields its definition
  # reads. The field itself is never downloaded: a client computes it.
  defp put_definition(include, root, chain, name, permission_checking?) do
    root
    |> mapped_chains(chain)
    |> Enum.reduce(include, fn mapped, acc ->
      owner_type = Entity.path_target(root, mapped)
      definition = Derived.definition(owner_type, name)

      put_definition_sources(acc, root, mapped, owner_type, definition, permission_checking?)
    end)
  end

  defp put_definition_sources(
         include,
         _root,
         _chain,
         _owner_type,
         {:value, _value},
         _permission_checking?
       ),
       do: include

  defp put_definition_sources(
         include,
         root,
         chain,
         owner_type,
         {:name, name},
         permission_checking?
       ) do
    {relationship_names, [last_name]} =
      name
      |> List.wrap()
      |> Enum.split(-1)

    name_chain = chain ++ relationship_names
    with_path = put_path_include(include, root, name_chain)

    if derived_at?(owner_type, relationship_names, last_name) do
      put_definition(with_path, root, name_chain, last_name, permission_checking?)
    else
      with_path
    end
  end

  defp put_definition_sources(
         include,
         root,
         chain,
         owner_type,
         {:concat, operands},
         permission_checking?
       ) do
    Enum.reduce(operands, include, fn operand, acc ->
      put_definition_sources(acc, root, chain, owner_type, operand, permission_checking?)
    end)
  end

  defp put_definition_sources(
         include,
         root,
         chain,
         _owner_type,
         {:condition, clauses},
         permission_checking?
       ),
       do: put_clause_reads(include, root, [chain], clauses, permission_checking?)

  defp put_definition_sources(
         include,
         root,
         chain,
         owner_type,
         {:if, clauses, then_value, else_value},
         permission_checking?
       ) do
    include
    |> put_clause_reads(root, [chain], clauses, permission_checking?)
    |> put_definition_sources(root, chain, owner_type, then_value, permission_checking?)
    |> put_definition_sources(root, chain, owner_type, else_value, permission_checking?)
  end

  defp put_definition_sources(
         include,
         root,
         chain,
         _owner_type,
         {:query, term},
         permission_checking?
       ) do
    {_owner_type, source_chain} = term.source
    {hops, [set_name]} = Enum.split(source_chain, -1)
    set_owner_chain = chain ++ hops
    set_owner_type = Entity.path_target(root, set_owner_chain)

    {with_set, set_chains} =
      if Derived.declared?(set_owner_type, set_name) do
        {put_definition(include, root, set_owner_chain, set_name, permission_checking?),
         mapped_chains(root, List.insert_at(set_owner_chain, -1, set_name))}
      else
        set_chain = List.insert_at(set_owner_chain, -1, set_name)
        narrowing = definition_narrowing(term, root, set_chain, chain)

        {put_source_set(include, root, set_chain, narrowing), [set_chain]}
      end

    Enum.reduce(set_chains, with_set, fn set_chain, acc ->
      sort_reads =
        for {key, _direction} <- term.sort,
            is_atom(key),
            Derived.declared?(term.entity, key),
            do: {set_chain, key}

      acc
      |> put_clause_reads(root, [set_chain, chain], term.filter, permission_checking?)
      |> put_derived_reads(root, sort_reads, permission_checking?)
      |> put_included_terms(root, set_chain, term.include, permission_checking?)
    end)
  end

  defp put_derived_reads(include, root, reads, permission_checking?) do
    Enum.reduce(reads, include, fn {chain, name}, acc ->
      put_definition(acc, root, chain, name, permission_checking?)
    end)
  end

  # What a term reads beside the rows it returns: the sets its quantifiers read, the rows along its
  # filter's paths, and the rows its type's rules read when a client checks them. The sets go first,
  # so a path's relationship joining one keeps its narrowing.
  defp put_embedded_includes(include, term, permission_checking?) do
    include
    |> put_term_derived_sources(term, permission_checking?)
    |> put_quantified_sets(term, permission_checking?)
    |> put_path_includes(term)
    |> put_policy_includes(term.entity, [], permission_checking?)
  end

  # What a template reads off the rows a derived field holds: the rows their rules read when a client
  # checks permissions, and what an include of the field includes, off every source of those rows.
  defp put_included_rows(include, root, rows_chains, included, permission_checking?) do
    Enum.reduce(rows_chains, include, fn rows_chain, acc ->
      acc
      |> put_policy_includes(root, rows_chain, permission_checking?)
      |> put_included_terms(root, rows_chain, included, permission_checking?)
    end)
  end

  # Includes read from the row a chain leads to: a relationship embedded with what it includes, and
  # a derived field by the rows it is computed from, what it includes read off those rows. The rows
  # an include holds are the ones a template reads, so a client checking permissions gets the rows
  # their rules read with them.
  defp put_included_terms(include, root, chain, included, permission_checking?) do
    entity_type = Entity.path_target(root, chain)

    Enum.reduce(included, include, fn {name, sub_term}, acc ->
      cond do
        not Derived.declared?(entity_type, name) ->
          name_chain = List.insert_at(chain, -1, name)

          acc
          |> put_path_include(root, name_chain)
          |> put_policy_includes(root, name_chain, permission_checking?)
          |> put_included_terms(root, name_chain, sub_term.include, permission_checking?)

        sub_term == nil ->
          put_definition(acc, root, chain, name, permission_checking?)

        true ->
          rows_chains = mapped_chains(root, List.insert_at(chain, -1, name))

          acc
          |> put_definition(root, chain, name, permission_checking?)
          |> put_included_rows(root, rows_chains, sub_term.include, permission_checking?)
      end
    end)
  end

  # A to-one include carries no clauses, so a path's relationship joins one already embedded by
  # adding what it includes - and a set a quantifier embedded keeps its narrowing.
  defp put_path_include(include, _entity_type, []), do: include

  defp put_path_include(include, entity_type, [relationship_name | later_names]) do
    target_type = Entity.related_type(entity_type, relationship_name)
    included = Map.get(include, relationship_name, %Query{entity: target_type})
    nested = put_path_include(included.include, target_type, later_names)

    Map.put(include, relationship_name, %{included | include: nested})
  end

  defp put_path_includes(include, term) do
    term.filter
    |> Stage.relationship_chains()
    |> Enum.flat_map(&mapped_chains(term.entity, &1))
    |> Enum.reduce(include, &put_path_include(&2, term.entity, &1))
  end

  # The chains the rules of the type a chain leads to read, embedded under it when a client checks
  # permissions - each up to its first type no session may read.
  defp put_policy_includes(include, _root, _chain, false), do: include

  defp put_policy_includes(include, root, chain, true) do
    target_type = Entity.path_target(root, chain)

    target_type
    |> Policy.related_chains()
    |> Enum.map(&Policy.readable_prefix(target_type, &1))
    |> Enum.reject(&(&1 == []))
    |> Enum.uniq()
    |> Enum.reduce(include, &put_rule_include(&2, root, chain, &1))
  end

  # The set at the end of a chain, embedded with the given narrowing - nil for the whole set - and
  # the rows before it as they are, a set there keeping the narrowing it has (see linked_sets/3).
  # Two narrowings of one set join with or and a whole one wins, an authored include among them - a
  # render embeds into a map of its own, which leaves its authored includes as written (see
  # embed/2).
  defp put_quantified_set(include, entity_type, [name], narrowing) do
    target_type = Entity.related_type(entity_type, name)

    case Map.fetch(include, name) do
      :error ->
        Map.put(include, name, %Query{entity: target_type, filter: narrowing || []})

      {:ok, included} ->
        joined = joined_narrowing([included.filter, narrowing])

        Map.put(include, name, %{included | filter: joined || []})
    end
  end

  defp put_quantified_set(include, entity_type, [name | later_names], narrowing) do
    target_type = Entity.related_type(entity_type, name)
    included = Map.get(include, name, %Query{entity: target_type})
    nested = put_quantified_set(included.include, target_type, later_names, narrowing)

    Map.put(include, name, %{included | include: nested})
  end

  # Every set the term's quantifiers read, the narrowings of one set joined before any is embedded,
  # so the order quantifiers are written in decides nothing.
  defp put_quantified_sets(include, term, permission_checking?) do
    term.filter
    |> quantified_sets(term.entity, [[]])
    |> put_sets(include, term.entity, permission_checking?)
  end

  # A rule's chain is embedded the way a path's is, except that a set along it is embedded whole: the
  # client answers the rule over the rows it holds, and a narrowing another quantifier or the query
  # itself gave the set leaves out rows the rule may be answered by. The chain before the rule's own
  # - the include it is read under - stays as it is.
  defp put_rule_include(include, root, [], rule_chain),
    do: put_whole_sets(include, root, rule_chain)

  defp put_rule_include(include, entity_type, [name | later_names], rule_chain) do
    target_type = Entity.related_type(entity_type, name)
    included = Map.get(include, name, %Query{entity: target_type})
    nested = put_rule_include(included.include, target_type, later_names, rule_chain)

    Map.put(include, name, %{included | include: nested})
  end

  defp put_sets(sets, include, entity_type, _permission_checking?) do
    sets
    |> Enum.group_by(fn {chain, _narrowing} -> chain end, fn {_chain, narrowing} -> narrowing end)
    |> Enum.sort()
    |> Enum.reduce(include, fn {chain, narrowings}, acc ->
      narrowing = joined_narrowing(narrowings)

      put_quantified_set(acc, entity_type, chain, narrowing)
    end)
  end

  defp put_source_set(include, entity_type, [name], narrowing),
    do: put_quantified_set(include, entity_type, [name], narrowing)

  defp put_source_set(include, entity_type, [name | later_names], narrowing) do
    target_type = Entity.related_type(entity_type, name)
    included = Map.get(include, name, %Query{entity: target_type})
    whole = if set_hop?(entity_type, name), do: %{included | filter: []}, else: included
    nested = put_source_set(whole.include, target_type, later_names, narrowing)

    Map.put(include, name, %{whole | include: nested})
  end

  # What a term reads through derived fields, embedded from its root row: the definitions its
  # filter and sort read, and its derived includes with what they include.
  defp put_term_derived_sources(include, term, permission_checking?) do
    sort_reads =
      for {key, _direction} <- term.sort,
          is_atom(key),
          Derived.declared?(term.entity, key),
          do: {[], key}

    derived_includes =
      Map.filter(term.include, fn {name, _sub_term} -> Derived.declared?(term.entity, name) end)

    include
    |> put_derived_reads(
      term.entity,
      clause_derived_reads(term.filter, term.entity, [[]]),
      permission_checking?
    )
    |> put_derived_reads(term.entity, sort_reads, permission_checking?)
    |> put_included_terms(term.entity, [], derived_includes, permission_checking?)
  end

  # Every set along the given chain embedded whole, and every to-one as it is.
  defp put_whole_sets(include, _entity_type, []), do: include

  defp put_whole_sets(include, entity_type, [name | later_names]) do
    target_type = Entity.related_type(entity_type, name)
    included = Map.get(include, name, %Query{entity: target_type})
    whole = if set_hop?(entity_type, name), do: %{included | filter: []}, else: included
    nested = put_whole_sets(whole.include, target_type, later_names)

    Map.put(include, name, %{whole | include: nested})
  end

  # A derived field's source reads every row along its chain: a set before its last one is the
  # rows every path reaches, flattened, so it is downloaded whole whatever else narrows it.
  # Each quantifier's set as the chain of relationships to it from the queried row, paired with what
  # narrows it - nil for the whole set.
  #
  # A set a derived field holds is no set of its own: its rows are its definition's, whose sources
  # are embedded for it (see put_definition/5), so a quantifier over one embeds nothing here beyond
  # what its condition's nested quantifiers read. A chain through one is read as the chains to the
  # sets its rows come from (see mapped_chains/2).
  defp quantified_sets(clauses, entity_type, prefixes) do
    Enum.flat_map(clauses, fn
      {:or, alternatives} ->
        Enum.flat_map(alternatives, &quantified_sets(&1, entity_type, prefixes))

      {quantifier, {source, inner}} when quantifier in @quantifiers ->
        chain = source_chain(source, prefixes)

        quantifier_sets(quantifier, chain, inner, entity_type, prefixes) ++
          linked_sets(entity_type, chain, source)

      _triple ->
        []
    end)
  end

  defp quantifier_sets(quantifier, chain, inner, entity_type, prefixes) do
    nested_sets = quantified_sets(inner, entity_type, [chain | prefixes])

    if derived_end?(entity_type, chain) do
      nested_sets
    else
      sets =
        for mapped <- mapped_chains(entity_type, chain),
            do: {mapped, set_narrowing(quantifier, inner, entity_type, mapped, prefixes)}

      sets ++ nested_sets
    end
  end

  defp reads_derived?({name, _operator, operand}, scope) do
    derived_name?(name, scope) or derived_name?(operand_name(operand), scope)
  end

  # The chains to the sets a definition of a field holding rows reads its rows off: its query's, or
  # every branch's, nil holding none.
  defp row_sources({:query, %Query{source: {_owner_type, source_chain}}}), do: [source_chain]

  defp row_sources({:if, _clauses, then_value, else_value}),
    do: row_sources(then_value) ++ row_sources(else_value)

  defp row_sources({:value, nil}), do: []

  # A condition part that reads nothing outside the set's row - the row a nested quantifier binds
  # inside it is its own, so a name reaching a row above counts from the depth it is written at.
  defp self_contained?({:or, alternatives}, depth) do
    Enum.all?(alternatives, fn alternative ->
      Enum.all?(alternative, &self_contained?(&1, depth))
    end)
  end

  defp self_contained?({quantifier, {source, inner}}, depth) when quantifier in @quantifiers do
    within?(source, depth) and Enum.all?(inner, &self_contained?(&1, depth + 1))
  end

  defp self_contained?({name, _operator, operand}, depth) do
    within?(name, depth) and within?(operand_name(operand), depth)
  end

  defp set_hop?(entity_type, name) do
    to_many? =
      match?({_name, [_target], _opts}, List.keyfind(entity_type.__relationships__(), name, 0))

    to_many? or match?(%{to_many?: true}, Entity.inverse_relationship(entity_type, name))
  end

  # Only a set read off its rows' own reference field can be narrowed - a set the client reads
  # through ids is downloaded whole - and only by what decides any and none: the related rows the
  # condition matches. all is decided by the rows it does not match.
  defp set_narrowing(quantifier, inner, entity_type, chain, prefixes) do
    {owner_chain, [set_name]} = Enum.split(chain, -1)

    owner_type = Entity.path_target(entity_type, owner_chain)
    scope = Enum.map([chain | prefixes], &Derived.path_target(entity_type, &1))

    with true <- quantifier in [:any, :none],
         %{reference?: true} <- Entity.inverse_relationship(owner_type, set_name),
         [_clause | _clauses] = narrowing <-
           inner
           |> narrowed_clauses(scope)
           |> Enum.filter(&self_contained?(&1, 0))
           |> Stage.normalized_filter() do
      narrowing
    else
      _whole -> nil
    end
  end

  defp source_chain({:outer, levels, hops}, prefixes), do: Enum.at(prefixes, levels) ++ hops

  defp source_chain(hops, [prefix | _rows_above]), do: prefix ++ hops

  defp source_start({:outer, levels, hops}, scope), do: {Enum.at(scope, levels), hops}

  defp source_start(hops, [entity_type | _rows_above]), do: {entity_type, hops}

  defp narrowed_clause({:or, alternatives}, scope) do
    narrowed = Enum.map(alternatives, &narrowed_clauses(&1, scope))

    if Enum.any?(narrowed, &(&1 == [])) do
      []
    else
      [{:or, narrowed}]
    end
  end

  # An any narrows the download whatever a reader may not see, by its condition narrowed the same
  # way. none and all do not - a reader seeing fewer related rows can answer either true where the
  # stored rows answer false.
  #
  # A derived value, or an any over a derived set, is computed over the rows a reader holds, which
  # can be fewer than are stored - so no comparison of one bounds the set safely, and it
  # is dropped.
  defp narrowed_clause({:any, {source, clauses}}, scope) do
    {start_type, hops} = source_start(source, scope)

    if derived_end?(start_type, hops) do
      []
    else
      related_type = Derived.path_target(start_type, hops)

      [{:any, {source, narrowed_clauses(clauses, [related_type | scope])}}]
    end
  end

  defp narrowed_clause({quantifier, {_source, _clauses}}, _scope)
       when quantifier in [:all, :none],
       do: []

  defp narrowed_clause(triple, scope) do
    if missing_path_match?(triple) or reads_derived?(triple, scope),
      do: [],
      else: [triple]
  end

  defp narrowed_clauses(clauses, scope), do: Enum.flat_map(clauses, &narrowed_clause(&1, scope))

  defp within?({:outer, levels, _name}, depth), do: levels <= depth

  defp within?(_name, _depth), do: true
end
