defmodule Hologram.Query.Window do
  @moduledoc false

  alias Hologram.Entity
  alias Hologram.Entity.Derived
  alias Hologram.Policy
  alias Hologram.Query
  alias Hologram.Query.Stage

  @quantifiers [:all, :any, :none]

  # What a query downloads, as opposed to what it answers. A client holds the rows its queries
  # could need rather than the ones they select right now, so changing a value re-runs the query
  # over what is already there instead of asking for more.

  @doc """
  Returns the window term of the given query term - the same query with the predicates that
  cannot say anything about the download taken out, and an included set the client reads through
  ids downloaded whole.

  A predicate is dropped when a PLACEHOLDER stands on either side of it - as the value, whatever the
  operator, or as the attribute being compared. Both are unknown when the window is derived, so
  the predicate bounds nothing, and the answer for every value it may take has to be in what
  arrives. What keeps that download finite is elsewhere - the model bounds an enum or a boolean by
  what it declares, and the read policy bounds a reference by the rows the actor may see, which is
  applied to the download in any case.

  A predicate comparing to a LITERAL stays: an app whose only query asks for todo projects is
  saying the others are never needed. So does one comparing two ATTRIBUTES of the row
  (`end_date < start_date`) - it says something about the row whatever value anything takes - and
  one reading a PATH, by the same rule, unless a missing related row satisfies it (see below):
  `channel.archived == false` keeps the messages of unarchived channels.

  An included set the client reads through the ids filed for its row - a to-many, or an inverse of
  one - keeps none of its predicates: it is downloaded whole, every related row the read rules
  admit. A row on the wire states the whole set it names, and every window holding the row shares
  that one set in the client, so a narrowed set would stand for the complete one another window
  reads, and an edge the narrowing leaves out would be reported gone. The narrowing still applies
  where the query is answered, so the rows its paths read are embedded as for any filter. A set
  read off its rows' own reference field - an inverse of a to-one - and a to-one are narrowed as
  any query is.

  A PATH reads rows the query does not return, and the client answers the query over what it
  holds, so every path the filter names - kept or dropped, on either side of a comparison, inside
  alternatives - has its relationships embedded in the window as to-one includes, merged with the
  query's own. The related rows arrive with the window and are kept current with it, and a change
  to one reaches the window the way a change to an included row does.

  A path to a row a reader may not read reads as missing for that reader, while the window reads
  the row as stored. So a path predicate that matches a missing value - `channel.archived != true`,
  `channel.name == nil`, `channel.kind in [nil, :dm]`, `channel.kind not in [:dm]`, or an equality
  or inequality with another attribute, `x == channel.y` - bounds nothing: the window would leave
  out a row the reader's own answer keeps. It is dropped. One that never matches a missing value -
  an equality with a value, `!= nil`, a membership without nil, a negated one with nil, an ordering
  comparison - stays.

  A DISJUNCTION cannot drop a predicate the same way. Dropping a conjunct widens what arrives,
  which is safe - dropping an alternative narrows it, and `status == :todo or owner_id == ^user_id`
  would then download only the todo rows, while the query also answers for a user's own rows in
  every other status. So each alternative is narrowed to its literal predicates and the disjunction
  stays, unless an alternative loses every predicate: that alternative admits every row for some
  value of its placeholders, so the disjunction bounds nothing and is dropped whole, the clauses
  beside it staying. A nested disjunction follows the same rule from the inside out. Narrowing
  can move an alternative among the others, so the filter is put back in canonical order - two
  queries differing only in a pinned alternative must name one window.

  A QUANTIFIER reads the rows of a related set, and the client answers it over the ones it holds,
  so every set a quantifier reads - nested ones and the rows along its source included - is
  embedded in the window as an include, the rows its condition's paths read with it, and a change
  to one of them reaches the window the way a change to an included row does. A set read off its
  rows' own reference field is narrowed by the quantifier's condition, as the queried rows are by
  theirs: `any` and `none` are decided by the related rows the condition matches, so only those are
  downloaded, the parts of the condition that bound nothing - a placeholder, a row above the set -
  left out. `all` is decided by the rows the condition does NOT match, so its set is downloaded
  whole, and so is a set the client reads through ids, for the reason above. A set before the last
  link of a source is downloaded whole too, whatever else narrows it, since every row of it leads
  to related rows. Two narrowings of one set are joined with `or`, and a whole one wins.

  The window runs over every row, and a client is handed the rows it may read - so a predicate may
  only bound the download when a client reading fewer related rows can never answer it true where
  the window answers false. An `any` passes: fewer related rows make it false more often, never
  true, so it stays, narrowed by these same rules - one losing every predicate still asks that the
  set holds a row. `none` and `all` fail it - a channel whose only flagged message a reader may not
  read has none of that reader's flagged messages - so they are dropped, widening the download.

  A client that checks permissions answers each rule over what it holds too, and a rule can read
  rows other than the one it decides about - the row a `via:` leads to, the rows before the last
  relationship of a `to:` reference, the rows along a `when:` path. So when the build has a page
  checking permissions on the client, the chains the rules of the type a query returns read (see
  `Hologram.Policy.related_chains/1`) are embedded the way a path's relationships are, and so are
  those of every type it includes, under that include. A row embedded for a path or for a rule
  gets no rule chains of its own: the template never sees it, whatever a delegation reads through
  it is in the delegating type's chains already, and a rule reading a row of its own type would
  otherwise never stop embedding.

  Sort, skip and take are emptied rather than dropped. They shape what a query answers rather
  than what it downloads, so two queries reading the same rows in different orders share one
  window - but a window IS a query term and is run as one, so it keeps a term's shape and states
  that it asks for every row, in no order.

  KNOWN CONSEQUENCE, recorded rather than worked around: a filtered include of a to-many or of an
  inverse of one downloads the whole set, until narrowed includes give way to derived fields. A
  render answers the authored term (see `embed/2`), so a first paint can carry a narrowed set for a
  row the client does not hold yet, until the window's fill replaces it with the whole one. The
  same holds for a quantifier over a set the authored term also includes narrowed: the render
  carries the authored set, so the browser's first answer of the quantifier can differ from the
  server's until the fill lands.

  KNOWN CONSEQUENCE, recorded rather than worked around: a query whose only bound is a placeholder
  downloads everything the policy admits. A thirty-day message window written as
  `created_at > ^cutoff` downloads the channel's whole history, because a cutoff computed
  per render says nothing at compile time. Bounding it needs the thirty days written into the
  query itself - a relative bound the compiler can read and the server evaluates per run - which
  the filter surface does not offer yet.
  """
  @spec derive(Query.t(), boolean) :: Query.t()
  def derive(term, permission_checking?) do
    filter =
      term.filter
      |> window_clauses([term.entity])
      |> Stage.normalized_filter()

    include =
      term.include
      |> Enum.reject(fn {name, _sub_term} -> Derived.declared?(term.entity, name) end)
      |> Map.new(fn {name, sub_term} ->
        {name, downloaded(derive(sub_term, permission_checking?), term.entity, name)}
      end)
      |> put_embedded_includes(term, permission_checking?)

    %Query{entity: term.entity, filter: filter, include: include}
  end

  @doc """
  Returns the given query term with the relationships its filters' paths go through embedded as
  to-one includes, merged with its own, the sub-terms of its includes embedded the same way - the
  term that reads the rows a path reads alongside the rows it returns. When the build has a page
  checking permissions on the client, the chains the rules of the types it returns and includes
  read are embedded beside them, the way `derive/2` embeds them into the window.

  The term's own clauses stay as written, a narrowed include's filter included - it answers the
  query as authored, where the window downloads such a set whole. The sets its quantifiers read are
  embedded the way the window embeds them, narrowed alike, beside the authored includes - an
  authored include of the same set is left as authored.

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
      |> Enum.filter(fn
        {_relationships, {:placeholder, _name}} -> false
        {relationships, name} -> derived_at?(root, relationships, name)
      end)

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

  # What a derived field's query narrows its set by in the window: its conditions about the set's
  # rows alone - none reading the owning row, which says nothing at build time - and only for a set
  # read off its rows' own reference field, as a quantifier's set is narrowed.
  defp definition_narrowing(term, root, set_chain, owner_chain) do
    {set_owner_chain, [set_name]} = Enum.split(set_chain, -1)
    set_owner_type = Entity.path_target(root, set_owner_chain)
    scope = [term.entity, Entity.path_target(root, owner_chain)]

    with %{reference?: true} <- Entity.inverse_relationship(set_owner_type, set_name),
         [_clause | _clauses] = narrowing <-
           term.filter
           |> window_clauses(scope)
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

  defp derived_name?({:placeholder, _name}, _scope), do: false

  defp derived_name?({:outer, levels, name}, scope),
    do: derived_name?(name, [Enum.at(scope, levels)])

  defp derived_name?(name, [entity_type | _rows_above]) do
    {relationship_names, [last_name]} =
      name
      |> List.wrap()
      |> Enum.split(-1)

    derived_at?(entity_type, relationship_names, last_name)
  end

  # A set the client reads through the ids filed for its row - a to-many, or an inverse of one - is
  # downloaded whole: a row states the whole set it names, so a narrowed one would stand for the
  # complete set every other window reads, and an edge the narrowing leaves out would be reported
  # gone. Its window is derived first, so the rows its filter's paths read stay embedded - the
  # client still applies the narrowing when it answers the query.
  defp downloaded(derived_sub_term, entity_type, name) do
    if read_through_ids?(entity_type, name) do
      %{derived_sub_term | filter: []}
    else
      derived_sub_term
    end
  end

  # Narrowings of one set download what any of them needs: one disjunction of their clause lists,
  # each list once, flattened from a disjunction they already form. A whole set - nil, or an empty
  # filter such as an authored include's with no clauses - needs everything.
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
  # from - the chains the window embeds. A field choosing its rows with if holds the rows of every
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
  # embedded relationship keeps its own clauses and gains what the embedded one includes.
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

  defp placeholder?({:placeholder, _name}), do: true

  defp placeholder?(values) when is_list(values), do: Enum.any?(values, &placeholder?/1)

  defp placeholder?(_value), do: false

  # A path holds names only, never a placeholder, so only its value can bound nothing.
  defp placeholder_bound?({path, _operator, value}) when is_list(path), do: placeholder?(value)

  defp placeholder_bound?({name, _operator, value}), do: placeholder?(name) or placeholder?(value)

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

  # A to-one include carries no clauses, so a path's relationship joins one the window already
  # has by adding what it includes - and a set a quantifier embedded keeps its narrowing.
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
  # permissions.
  defp put_policy_includes(include, _root, _chain, false), do: include

  defp put_policy_includes(include, root, chain, true) do
    root
    |> Entity.path_target(chain)
    |> Policy.related_chains()
    |> Enum.reduce(include, &put_path_include(&2, root, chain ++ &1))
  end

  # The set at the end of a chain, embedded with the given narrowing - nil for the whole set - and
  # the rows before it as they are, a set there keeping the narrowing it has (see linked_sets/3).
  # Two narrowings of one set join with or and a whole one wins, an authored narrowing included - a
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

  defp put_sets(sets, include, entity_type, _permission_checking?) do
    sets
    |> Enum.group_by(fn {chain, _narrowing} -> chain end, fn {_chain, narrowing} -> narrowing end)
    |> Enum.sort()
    |> Enum.reduce(include, fn {chain, narrowings}, acc ->
      narrowing = joined_narrowing(narrowings)

      put_quantified_set(acc, entity_type, chain, narrowing)
    end)
  end

  # A derived field's source reads every row along its chain: a set before its last one is the
  # rows every path reaches, flattened, so it is downloaded whole whatever else narrows it.
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

  defp read_through_ids?(entity_type, name) do
    case Entity.inverse_relationship(entity_type, name) do
      nil ->
        match?({_name, [_target], _opts}, List.keyfind(entity_type.__relationships__(), name, 0))

      inverse ->
        not inverse.reference?
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
           |> window_clauses(scope)
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

  defp window_clause({:or, alternatives}, scope) do
    narrowed = Enum.map(alternatives, &window_clauses(&1, scope))

    if Enum.any?(narrowed, &(&1 == [])) do
      []
    else
      [{:or, narrowed}]
    end
  end

  # An any narrows the download whatever a reader may not see, by its condition narrowed the same
  # way. none and all do not - a reader seeing fewer related rows can answer either true where the
  # window, reading every row, answers false.
  #
  # A derived value, or an any over a derived set, is computed over the rows a reader holds, which
  # can be fewer than the window reads - so no comparison of one bounds the download safely, and it
  # is dropped like one a placeholder stands in.
  defp window_clause({:any, {source, clauses}}, scope) do
    {start_type, hops} = source_start(source, scope)

    if derived_end?(start_type, hops) do
      []
    else
      related_type = Derived.path_target(start_type, hops)

      [{:any, {source, window_clauses(clauses, [related_type | scope])}}]
    end
  end

  defp window_clause({quantifier, {_source, _clauses}}, _scope) when quantifier in [:all, :none],
    do: []

  defp window_clause(triple, scope) do
    if placeholder_bound?(triple) or missing_path_match?(triple) or reads_derived?(triple, scope),
      do: [],
      else: [triple]
  end

  defp window_clauses(clauses, scope), do: Enum.flat_map(clauses, &window_clause(&1, scope))

  defp within?({:outer, levels, _name}, depth), do: levels <= depth

  defp within?(_name, _depth), do: true
end
