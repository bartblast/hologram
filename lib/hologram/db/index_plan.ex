defmodule Hologram.DB.IndexPlan do
  @moduledoc false

  # The indexes the framework builds beside the model's own constraints are derived from what the
  # server runs rather than declared. Each statement the server runs yields access needs - the
  # columns of one table an index would have to lead with to serve it - and the needs of every
  # statement are merged into the fewest btree indexes that serve them all.
  #
  # A need mirrors the statement Hologram.DB.QueryCompiler.compile/3 builds, condition by
  # condition, since an index serves only a condition Postgres can match against it. Statements
  # reach Postgres unnamed and are planned with their values, so a placeholder serves as well as
  # a literal.
  #
  # Postgres answers an OR from indexes only with a BitmapOr, whose every arm needs an index
  # condition of its own. It pushes the conditions ANDed beside an OR into each arm, and an arm's
  # own conditions into the arms of an OR nested in it, but never a condition of one OR into the
  # arms of another beside it - so each OR gives its arms as needs of their own, each with what
  # stands beside it, and two ORs beside each other are never crossed.

  alias Hologram.Entity
  alias Hologram.Entity.Derived
  alias Hologram.Query
  alias Hologram.Query.Stage

  # The most needs the ORs of one clause list may add between them. An OR that would take them
  # past it adds nothing, and is left to the conditions beside it: an index per arm costs every
  # write, and a statement with that many alternatives is better served by what's ANDed with them.
  @max_or_needs 8

  @range_operators [:<, :<=, :>, :>=]

  # A condition Postgres can match against an index. An equality on a value (`=`) fixes its column,
  # so an index holding it in any position before a range or an ordering still returns its rows in
  # order. One matching a set of values (`= ANY`, `IS NULL`, or both ORed) narrows the scan as well,
  # but returns the rows of each value apart, so nothing after it is in order. A range narrows the
  # scan only in the last position.
  # A string's IS NULL is a set of its own kind (`:null`), since it reads the raw column alone.
  @typep conjunct ::
           {:eq, String.t()} | {:set, String.t()} | {:null, String.t()} | {:range, String.t()}

  @type need :: %{
          table: String.t(),
          eq: MapSet.t(String.t()),
          range: String.t() | nil,
          order: list(String.t())
        }

  @doc """
  Returns the access needs of the statement the given normalized query term compiles to with no
  policy, against the given mapping - each a map with :table, :eq (the columns an equality or a
  membership narrows to given values, in any order), :range (the one column a range narrows, or
  nil) and :order (the columns the statement's ordering reads after those, in order).

  A condition is served by an index when it compares a column of the queried row with a value:
  `==`, `in` and the four orderings, and `IS NULL` for a missing value. A string is served by its
  sort key, since its raw column is unbounded and no index holds it - except an equality or a
  membership on a string a unique index holds raw, which that index serves. A string's `IS NULL`
  reads the raw column, so only such an index serves it. A membership holding nil on an optional
  column is the OR of the membership and the `IS NULL` it compiles to. Anything else - an
  inequality, a search, a comparison between two attributes, a derived value, a path or a
  quantifier - is not served, and adds nothing.

  The served conditions ANDed in the filter give one need. Each OR in it adds a need per arm, the
  arm's served conditions with the ones beside the OR, and an arm holding an OR of its own adds a
  need per arm of that one as well. An OR with an arm no index serves can't be answered from
  indexes, and adds nothing, and so does one taking the ORs of its clause list past
  #{@max_or_needs} distinct needs between them. A need holding several ranges keeps the one the ordering
  leads with, and otherwise the lowest by column name.

  A statement with no OR an index serves that bounds its rows - a `take` or `one` - also orders
  from the index: its sort columns follow the need's, up to the first change of direction, a
  string's sort key or a placeholder, skipping a column an equality fixes. The `id` ending every
  ordering is kept only when it is the whole of it, as it is for a query naming no sort. A
  membership or a range on another column than the one the ordering leads with keeps the rows out
  of order, so then no sort column is kept, and a range on the column it leads with ends the
  need's ordering columns. Equalities fixing every column of the primary key or a unique index
  match one row at most, so they order nothing.

  A need the primary key serves is left out, and so is one whose equalities fix every column of a
  unique index, which serves it, a need with no column and a repeat.

  The related tables the statement's subqueries read give needs of their own, by the same rules,
  at every depth: a quantifier's set, the rows or the count of a derived field the statement reads,
  sorts by or includes, and an included set. Each probe of such a subquery matches the related
  rows to the row above it, so a set matched by its reference column - an inverse of a to-one -
  needs that column first, fixed like an equality, then its own conditions, and a bounded derived
  set its ordering after them. A range comparing a column with the row above is an index condition
  there too, each probe binding it. Its read rules add nothing there. Under an `any` ANDed at the top
  of the filter, Postgres may read the related rows first, so their own conditions are a need
  without the reference column as well. A set matched through a join table needs nothing - the join
  table's primary key and reverse index serve the link, and the related rows are then read by their
  ids. A set before a source's last link is read through a correlated subquery of its own, which
  needs its reference column when it is an inverse of a to-one. A path or a to-one reads its row by
  its id.
  """
  @spec needs(Query.t(), %{module => %{atom => any}}) :: list(need)
  def needs(term, mapping) do
    term
    |> level_needs(nil, mapping)
    |> Enum.concat(deeper_needs(term, mapping))
    |> Enum.uniq()
  end

  # The needs of one level of a statement - the queried row's, or a related table's a subquery
  # reads, matched to the row above by the given reference column (nil at the top), which an index
  # holds as a column an equality fixes: each probe of the subquery compares it with the row above's
  # id.
  defp level_needs(term, link, mapping) do
    entity_mapping = Map.fetch!(mapping, term.entity)
    unique_columns = unique_columns(entity_mapping)

    scope = %{
      entity_mapping: entity_mapping,
      leading_unique_columns: leading_unique_columns(entity_mapping),
      linked?: link != nil,
      raw_keys: raw_keys(entity_mapping, unique_columns),
      unique_columns: unique_columns
    }

    linked = fn path -> if link, do: [{:eq, link} | path], else: path end

    [plain | or_paths] =
      term.filter
      |> paths(scope)
      |> Enum.map(linked)

    plain_order =
      if or_paths == [] and bounded?(term) do
        order_columns(term.sort, fixed_columns(plain), scope)
      else
        []
      end

    [{plain, plain_order} | Enum.map(or_paths, &{&1, []})]
    |> Enum.reject(fn {path, _order} -> key_served?(path, entity_mapping) end)
    |> Enum.map(fn {path, order} -> path_need(path, order, scope) end)
    |> Enum.reject(&empty_need?/1)
  end

  # The needs of the related tables a statement's subqueries read: its quantifiers', the counts and
  # sets of the derived fields it reads or includes, and its includes', at every depth. The types
  # of the rows above a level are passed along, nearest first, for the names and sources reaching
  # them. Derived fields never read each other in a cycle - the build refuses one - so following
  # their definitions ends.
  defp deeper_needs(term, mapping) do
    context = %{mapping: mapping, outer: []}

    clause_level_needs(term.filter, term.entity, true, context) ++
      sort_level_needs(term.sort, term.entity, context) ++
      if(term.cardinality == :count,
        do: [],
        else: include_level_needs(term.include, term.entity, context)
      )
  end

  defp clause_level_needs(clauses, entity_type, top?, context) do
    Enum.flat_map(clauses, fn
      {:or, alternatives} ->
        Enum.flat_map(alternatives, &clause_level_needs(&1, entity_type, false, context))

      {quantifier, {source, inner}} when quantifier in [:all, :any, :none] ->
        quantifier_needs(quantifier, source, inner, entity_type, top?, context)

      {name, _operator, operand} ->
        name_level_needs(name, entity_type, context) ++
          operand_level_needs(operand, entity_type, context)
    end)
  end

  defp operand_level_needs({:attribute, name}, entity_type, context),
    do: name_level_needs(name, entity_type, context)

  defp operand_level_needs(_operand, _entity_type, _context), do: []

  # A name reading a derived field - of the row, of a row above or at the end of a path - reads what
  # its definition reads, on the row it is read on.
  defp name_level_needs(name, entity_type, context) do
    case derived_name(name, entity_type, context) do
      {owner_type, field_name, field_context} ->
        derived_needs(owner_type, field_name, field_context)

      nil ->
        []
    end
  end

  defp derived_name({:outer, levels, name}, _entity_type, context) do
    {outer_type, outer_context} = outer_row(context, levels)

    derived_name(name, outer_type, outer_context)
  end

  defp derived_name(name, entity_type, context) when is_atom(name) do
    if Derived.declared?(entity_type, name), do: {entity_type, name, context}
  end

  defp derived_name(path, entity_type, context) when is_list(path) do
    {hops, [name]} = Enum.split(path, -1)
    end_type = Entity.path_target(entity_type, hops)

    if Derived.declared?(end_type, name), do: {end_type, name, %{context | outer: []}}
  end

  defp derived_name(_name, _entity_type, _context), do: nil

  # The type of the row the given number of levels up, and the context its own level sees.
  defp outer_row(context, levels) do
    outer_type = Enum.at(context.outer, levels - 1)

    {outer_type, %{context | outer: Enum.drop(context.outer, levels)}}
  end

  # A quantifier reads the related rows its source leads to, matched to the row the source starts
  # at by the source's last link: an inverse of a to-one by its reference column, so the level needs
  # that column with the quantifier's conditions - except `all`'s, which it asks of every row as one
  # IS NOT TRUE no index serves - and an `any` ANDed at the top of the statement may be read the
  # other way round, starting from the related rows its conditions find, so those conditions are a
  # need of their own as well. A stored to-many or an inverse of one pairs them through a join table,
  # whose primary key and reverse index serve the link, so the related rows are read by their ids. A
  # derived set reads its rows through its definition's, and each link before the last through a
  # subquery of its own.
  defp quantifier_needs(quantifier, source, inner, entity_type, top?, context) do
    {source_type, source_context, chain} = quantifier_source(source, entity_type, context)
    {owner_hops, [set_name]} = Enum.split(chain, -1)
    owner_type = Derived.path_target(source_type, owner_hops)
    target_type = Derived.related_type(owner_type, set_name)
    asked = if quantifier == :all, do: [], else: inner

    set_needs =
      if Derived.declared?(owner_type, set_name) do
        derived_needs(owner_type, set_name, source_context)
      else
        level_term = inner_term(target_type, asked)
        read_first? = top? and quantifier == :any

        linked_level_needs(owner_type, set_name, level_term, read_first?, context.mapping)
      end

    inner_context = %{context | outer: [entity_type | context.outer]}

    earlier_link_needs(source_type, owner_hops, source_context) ++
      set_needs ++ clause_level_needs(inner, target_type, false, inner_context)
  end

  # The links of a source before its last - a derived set only ever ends a source: a to-one reads
  # its row by its id, and a set its rows in a correlated subquery matching them to the rows before,
  # by the reference column for an inverse of a to-one, which the subquery then needs, and through a
  # join table for a to-many.
  defp earlier_link_needs(start_type, links, context) do
    links
    |> Enum.reduce({start_type, []}, fn link, {link_type, acc} ->
      target_type = Entity.related_type(link_type, link)
      target_term = inner_term(target_type, [])

      {target_type,
       acc ++ linked_level_needs(link_type, link, target_term, false, context.mapping)}
    end)
    |> elem(1)
  end

  defp quantifier_source({:outer, levels, chain}, _entity_type, context) do
    {outer_type, outer_context} = outer_row(context, levels)

    {outer_type, outer_context, chain}
  end

  defp quantifier_source(chain, entity_type, context), do: {entity_type, context, chain}

  defp inner_term(entity_type, clauses) do
    %{Stage.normalize(entity_type) | filter: clauses, sort: []}
  end

  # The needs of a level read through the given relationship of the row above. An inverse of a
  # to-one matches its rows by their reference column, which each probe compares with the row
  # above's id - so it leads the level's needs, fixed like an equality - and a level Postgres may
  # read first, before the rows above, needs its own conditions alone too. A join table needs
  # nothing.
  defp linked_level_needs(owner_type, set_name, term, read_first?, mapping) do
    case Entity.inverse_relationship(owner_type, set_name) do
      %{reference?: true} = inverse ->
        first_needs = if read_first?, do: level_needs(term, nil, mapping), else: []

        level_needs(term, reference_column(inverse, mapping), mapping) ++ first_needs

      _join ->
        []
    end
  end

  defp reference_column(inverse, mapping) do
    mapping
    |> Map.fetch!(inverse.target)
    |> Map.fetch!(:columns)
    |> Enum.find(&(&1.source == {:relationship, inverse.forward}))
    |> Map.fetch!(:name)
  end

  defp sort_level_needs(sort, entity_type, context) do
    Enum.flat_map(sort, fn {name, _direction} -> name_level_needs(name, entity_type, context) end)
  end

  # An include reads its rows in a subquery: a to-many's or an inverse's matched to the row the way
  # a quantifier's set is, a to-one's by its id, and a derived field's through its definition,
  # embedding what that includes - and each included level's own includes and fields in turn.
  defp include_level_needs(include, entity_type, context) do
    Enum.flat_map(include, fn {name, sub_term} ->
      own_needs =
        cond do
          Derived.declared?(entity_type, name) ->
            derived_needs(entity_type, name, %{context | outer: []}, true)

          Entity.inverse_relationship(entity_type, name) != nil or to_many?(entity_type, name) ->
            linked_level_needs(entity_type, name, sub_term, false, context.mapping)

          true ->
            []
        end

      own_needs ++ sub_term_needs(sub_term, context)
    end)
  end

  defp sub_term_needs(nil, _context), do: []

  defp sub_term_needs(sub_term, context) do
    sub_context = %{context | outer: []}

    clause_level_needs(sub_term.filter, sub_term.entity, false, sub_context) ++
      sort_level_needs(sub_term.sort, sub_term.entity, sub_context) ++
      include_level_needs(sub_term.include, sub_term.entity, sub_context)
  end

  defp to_many?(entity_type, name) do
    match?({_name, [_target], _opts}, List.keyfind(entity_type.__relationships__(), name, 0))
  end

  # A derived field reads what its definition reads: a query's rows or count, matched to the row
  # through its source's last link, and the conditions and fields it computes from. A query's rows
  # embed what it includes, and are read in its order, only when the field is included - as a
  # quantifier's set or a count's source they are matched by id, in order only when bounded.
  defp derived_needs(entity_type, name, context, included? \\ false) do
    entity_type
    |> Derived.definition(name)
    |> definition_needs(entity_type, context, included?)
  end

  defp definition_needs(
         {:query, %{source: {owner_type, chain}} = term},
         _entity_type,
         context,
         included?
       ) do
    {earlier_links, [last_link]} = Enum.split(chain, -1)
    link_type = Derived.path_target(owner_type, earlier_links)
    owner_context = %{context | outer: []}

    rows_needs =
      if Derived.declared?(link_type, last_link) do
        derived_needs(link_type, last_link, owner_context)
      else
        linked_level_needs(link_type, last_link, term, false, context.mapping)
      end

    term_context = %{context | outer: [owner_type]}

    ordered? =
      included? or
        (term.cardinality != :count and
           (term.take != nil or term.skip != nil or term.cardinality == :one))

    earlier_link_needs(owner_type, earlier_links, owner_context) ++
      rows_needs ++
      clause_level_needs(term.filter, term.entity, false, term_context) ++
      if(ordered?, do: sort_level_needs(term.sort, term.entity, term_context), else: []) ++
      if(included?, do: include_level_needs(term.include, term.entity, term_context), else: [])
  end

  defp definition_needs({:if, clauses, then_value, else_value}, entity_type, context, included?) do
    clause_level_needs(clauses, entity_type, false, context) ++
      definition_needs(then_value, entity_type, context, included?) ++
      definition_needs(else_value, entity_type, context, included?)
  end

  defp definition_needs({:condition, clauses}, entity_type, context, _included?),
    do: clause_level_needs(clauses, entity_type, false, context)

  defp definition_needs({:concat, operands}, entity_type, context, _included?),
    do: Enum.flat_map(operands, &definition_needs(&1, entity_type, context, false))

  defp definition_needs({:name, name}, entity_type, context, _included?),
    do: name_level_needs(name, entity_type, context)

  defp definition_needs(_definition, _entity_type, _context, _included?), do: []

  defp bounded?(term),
    do: term.cardinality == :one or (term.cardinality == :set and term.take != nil)

  defp empty_need?(need), do: MapSet.size(need.eq) == 0 and need.range == nil and need.order == []

  defp fixed_columns(path), do: for({:eq, column} <- path, into: MapSet.new(), do: column)

  # A path the primary key or a unique index serves needs no index of its own - it has counted for
  # its OR already, since what serves it serves that arm.
  defp key_served?(path, entity_mapping) do
    Enum.any?(path, &match?({kind, "id"} when kind in [:eq, :set], &1)) or
      single_row?(fixed_columns(path), entity_mapping)
  end

  # How many needs the given paths give, leaving out the ones a key serves and counting a repeat
  # once, however its conditions are spelled.
  defp need_count(paths, scope) do
    paths
    |> Enum.reject(&key_served?(&1, scope.entity_mapping))
    |> Enum.map(&path_need(&1, [], scope))
    |> Enum.reject(&empty_need?/1)
    |> Enum.uniq()
    |> length()
  end

  # Equalities fixing every column of a unique index match one row at most, which needs no order.
  defp single_row?(fixed, entity_mapping) do
    Enum.any?(entity_mapping.indexes, fn {_name, index} ->
      index.unique and Enum.all?(index.columns, &MapSet.member?(fixed, &1))
    end)
  end

  # The paths of a clause list, the conditions ANDed in it first, then one per arm of each OR an
  # index can answer, each holding the ANDed ones too.
  defp paths(clauses, scope) do
    {ors, others} =
      clauses
      |> Enum.map(&spell_out_membership(&1, scope))
      |> Enum.split_with(&match?({:or, _alternatives}, &1))

    plain =
      others
      |> Enum.map(&conjunct(&1, scope))
      |> Enum.reject(&is_nil/1)

    or_paths =
      Enum.reduce(ors, [], fn {:or, alternatives}, acc ->
        combined = acc ++ or_paths(alternatives, plain, scope)

        if need_count(combined, scope) > @max_or_needs,
          do: acc,
          else: combined
      end)

    [plain | or_paths]
  end

  # An arm's paths without the empty ones: an arm with none is one no index serves.
  defp or_paths(alternatives, plain, scope) do
    arms =
      Enum.map(alternatives, fn alternative ->
        alternative
        |> paths(scope)
        |> Enum.reject(&(&1 == []))
      end)

    if [] in arms do
      []
    else
      arms
      |> Enum.concat()
      |> Enum.map(&Enum.sort(plain ++ &1))
    end
  end

  # A membership holding nil on an optional column compiles to an OR of the membership and an
  # IS NULL (see the query compiler's null_inclusive/3), so it is that OR here too - an OR beside it
  # is never crossed with it. On a required column the nil is dropped, and one holding nothing but
  # nil is the IS NULL alone.
  defp spell_out_membership({name, :in, values} = clause, scope)
       when is_atom(name) and is_list(values) do
    column = own_column(scope.entity_mapping, name)

    if column != nil and nil in values do
      case Enum.reject(values, &is_nil/1) do
        [] -> {name, :==, nil}
        given when column.null -> {:or, [[{name, :in, given}], [{name, :==, nil}]]}
        _given -> clause
      end
    else
      clause
    end
  end

  defp spell_out_membership(clause, _scope), do: clause

  defp path_need(path, order, scope) do
    # A membership or an IS NULL returns the rows of each value apart, so nothing after it is in
    # order.
    ordered_order =
      if Enum.any?(path, &match?({kind, _column} when kind in [:null, :set], &1)),
        do: [],
        else: order

    {_eq, _range, kept_order} = need_shape(path, ordered_order)
    held_path = hold_raw_strings(path, kept_order, scope)
    {eq, range, need_order} = need_shape(held_path, ordered_order)

    %{table: scope.entity_mapping.table, eq: eq, range: range, order: need_order}
  end

  defp need_shape(path, order) do
    eq = for {kind, column} <- path, kind in [:eq, :set, :null], into: MapSet.new(), do: column
    ranges = for {:range, column} <- path, not MapSet.member?(eq, column), uniq: true, do: column
    range = path_range(ranges, order)

    need_order =
      case {range, order} do
        {nil, columns} -> columns
        {range, [range | rest]} -> rest
        {_range, _columns} -> []
      end

    {eq, range, need_order}
  end

  # A unique index holds a string raw, bounded to what fits that index alone, so the raw column
  # never joins other columns in an index of the plan's: a long value would fail to be written.
  # A need that is exactly a unique index's leading columns keeps it, since that index serves it -
  # leaving out a raw IS NULL if it has to, which the rows that index finds are then checked for.
  # Any other compares the sort key beside the raw value, as the compiler does, and drops the
  # IS NULL, which no other column answers. An IS NULL is only ever on a column leading a unique
  # index, so dropping it leaves its OR's arm served by that index.
  defp hold_raw_strings(path, order, scope) do
    raw? = Enum.any?(path, fn {_kind, column} -> Map.has_key?(scope.raw_keys, column) end)
    without_null = Enum.reject(path, &match?({:null, _column}, &1))

    cond do
      not raw? ->
        path

      order == [] and unique_prefix?(path, scope.entity_mapping) ->
        path

      order == [] and without_null != [] and unique_prefix?(without_null, scope.entity_mapping) ->
        without_null

      true ->
        Enum.map(without_null, fn {kind, column} ->
          {kind, Map.get(scope.raw_keys, column, column)}
        end)
    end
  end

  defp unique_prefix?(path, entity_mapping) do
    columns = for {kind, column} <- path, kind != :range, into: MapSet.new(), do: column
    ranged? = Enum.any?(path, &match?({:range, _column}, &1))

    not ranged? and
      Enum.any?(entity_mapping.indexes, fn {_name, index} ->
        index.unique and
          MapSet.new(Enum.take(index.columns, MapSet.size(columns))) == columns
      end)
  end

  defp path_range(ranges, [first | _rest]) do
    if first in ranges, do: first, else: path_range(ranges, [])
  end

  defp path_range(ranges, []), do: Enum.min(ranges, fn -> nil end)

  @spec conjunct(Query.clause(), %{atom => any}) :: conjunct | nil
  defp conjunct({name, operator, operand}, scope) when is_atom(name) do
    case own_column(scope.entity_mapping, name) do
      nil -> nil
      column -> column_conjunct(column, operator, operand, scope)
    end
  end

  defp conjunct(_clause, _scope), do: nil

  # A range against a column of the row above is an index condition each probe of the subquery
  # binds, the way a value is - equality against one compiles to IS NOT DISTINCT FROM, which no
  # index serves.
  # Only a level matched to the row above binds it per probe - read first, before that row, the
  # range has nothing to compare with yet.
  defp column_conjunct(column, operator, {:attribute, {:outer, _levels, _name}}, scope)
       when operator in @range_operators do
    if scope.linked?, do: {:range, ordering_column(column, scope.entity_mapping)}
  end

  defp column_conjunct(_column, _operator, {:attribute, _other}, _scope), do: nil

  # A string's IS NULL reads its raw column, which only a unique index holds, and which that index
  # finds only when it leads with the column.
  defp column_conjunct(%{type: :string} = column, :==, nil, scope) do
    if MapSet.member?(scope.leading_unique_columns, column.name), do: {:null, column.name}
  end

  defp column_conjunct(column, :==, nil, _scope), do: {:set, column.name}

  defp column_conjunct(column, :==, _value, scope), do: {:eq, equality_column(column, scope)}

  defp column_conjunct(column, :in, _values, scope), do: {:set, equality_column(column, scope)}

  defp column_conjunct(column, operator, _value, scope) when operator in @range_operators do
    {:range, ordering_column(column, scope.entity_mapping)}
  end

  defp column_conjunct(_column, _operator, _value, _scope), do: nil

  # The column an index serves an equality on: a string's raw column when a unique index holds it,
  # which bounds its values and serves the comparison the compiler makes on it, and otherwise the
  # column an ordering reads.
  defp equality_column(%{type: :string} = column, scope) do
    if MapSet.member?(scope.unique_columns, column.name) do
      column.name
    else
      ordering_column(column, scope.entity_mapping)
    end
  end

  defp equality_column(column, _scope), do: column.name

  # A string orders and compares by its sort key, every other type by its own column.
  defp ordering_column(%{type: :string, source: {:attribute, name}}, entity_mapping) do
    entity_mapping.columns
    |> Enum.find(&(&1.source == {:sort_key, name}))
    |> Map.fetch!(:name)
  end

  defp ordering_column(column, _entity_mapping), do: column.name

  defp order_columns(sort, fixed, scope) do
    sort
    |> Enum.reduce_while({[], nil}, &order_step(&1, &2, fixed, scope))
    |> elem(0)
    |> Enum.reverse()
  end

  defp order_step({name, direction}, {_columns, previous_direction} = acc, fixed, scope) do
    column = order_column(name, scope)

    cond do
      column == nil ->
        {:halt, acc}

      MapSet.member?(fixed, equality_column(column, scope)) ->
        {:cont, acc}

      direction not in [:asc, :desc] or
          (previous_direction != nil and direction != previous_direction) ->
        {:halt, acc}

      true ->
        ordered_step(column, direction, acc, scope)
    end
  end

  defp ordered_step(%{type: :string} = column, direction, {columns, _previous}, scope) do
    {:halt, {[ordering_column(column, scope.entity_mapping) | columns], direction}}
  end

  # The id ends every ordering, normalization appending it when the query doesn't name it. After
  # another sort column it only breaks ties, which Postgres sorts cheaply, so it is kept only when
  # the ordering is the id alone.
  defp ordered_step(%{name: "id"}, direction, {[], _previous}, _scope),
    do: {:halt, {["id"], direction}}

  defp ordered_step(%{name: "id"}, _direction, acc, _scope), do: {:halt, acc}

  defp ordered_step(column, direction, {columns, _previous}, _scope),
    do: {:cont, {[column.name | columns], direction}}

  # The column an ordering entry sorts by from an index, or nil when no index can: a placeholder,
  # or a derived value, which no column holds.
  defp order_column(name, scope) when is_atom(name) do
    own_column(scope.entity_mapping, name)
  end

  defp order_column(_name, _scope), do: nil

  # The column a name of the row reads, as the query compiler resolves it: a declared attribute, a
  # to-one's reference field, or a system column. A derived field's name is none of these - the
  # entity validator refuses a field colliding with another - so it reads no column.
  defp own_column(%{columns: columns}, name) do
    column_name = Atom.to_string(name)

    Enum.find(columns, fn column ->
      case column.source do
        {:attribute, attribute_name} -> attribute_name == name
        {:relationship, relationship_name} -> "#{relationship_name}_id" == column_name
        :system -> column.name == column_name
        _other_source -> false
      end
    end)
  end

  # The sort key of each string a unique index holds raw, by the raw column's name.
  defp raw_keys(entity_mapping, unique_columns) do
    for %{type: :string, name: name} = column <- entity_mapping.columns,
        MapSet.member?(unique_columns, name),
        into: %{},
        do: {name, ordering_column(column, entity_mapping)}
  end

  defp leading_unique_columns(entity_mapping) do
    for {_name, %{unique: true, columns: [column | _rest]}} <- entity_mapping.indexes,
        into: MapSet.new(),
        do: column
  end

  defp unique_columns(entity_mapping) do
    for {_name, %{unique: true, columns: columns}} <- entity_mapping.indexes,
        column <- columns,
        into: MapSet.new(),
        do: column
  end
end
