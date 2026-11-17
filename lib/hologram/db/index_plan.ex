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

  alias Hologram.Query

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
  """
  @spec needs(Query.t(), %{module => %{atom => any}}) :: list(need)
  def needs(term, mapping) do
    entity_mapping = Map.fetch!(mapping, term.entity)
    unique_columns = unique_columns(entity_mapping)

    scope = %{
      entity_mapping: entity_mapping,
      raw_keys: raw_keys(entity_mapping, unique_columns),
      unique_columns: unique_columns
    }

    [plain | or_paths] = paths(term.filter, scope)

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
    |> Enum.uniq()
  end

  defp bounded?(term), do: term.cardinality == :one or term.take != nil

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
    path = hold_raw_strings(path, order, scope)

    eq = for {kind, column} <- path, kind in [:eq, :set, :null], into: MapSet.new(), do: column
    ranges = for {:range, column} <- path, not MapSet.member?(eq, column), uniq: true, do: column

    ordered_order =
      if Enum.any?(path, &match?({kind, _column} when kind in [:null, :set], &1)),
        do: [],
        else: order

    range = path_range(ranges, ordered_order)

    need_order =
      case {range, ordered_order} do
        {nil, columns} -> columns
        {range, [range | rest]} -> rest
        {_range, _columns} -> []
      end

    %{table: scope.entity_mapping.table, eq: eq, range: range, order: need_order}
  end

  # A unique index holds a string raw, bounded to what fits that index alone, so the raw column
  # never joins other columns in an index of the plan's: a long value would fail to be written.
  # A need that is exactly a unique index's leading columns keeps it, since that index serves it.
  # Any other compares the sort key beside the raw value, as the compiler does, and drops a raw
  # IS NULL, which no other column answers.
  defp hold_raw_strings(path, order, scope) do
    raw? = Enum.any?(path, fn {_kind, column} -> Map.has_key?(scope.raw_keys, column) end)

    cond do
      not raw? ->
        path

      order == [] and unique_prefix?(path, scope.entity_mapping) ->
        path

      true ->
        Enum.flat_map(path, fn
          {:null, _raw_column} -> []
          {kind, column} -> [{kind, Map.get(scope.raw_keys, column, column)}]
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

  defp column_conjunct(_column, _operator, {:attribute, _other}, _scope), do: nil

  # A string's IS NULL reads its raw column, which only a unique index holds.
  defp column_conjunct(%{type: :string} = column, :==, nil, scope) do
    if MapSet.member?(scope.unique_columns, column.name), do: {:null, column.name}
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

  defp unique_columns(entity_mapping) do
    for {_name, %{unique: true, columns: columns}} <- entity_mapping.indexes,
        column <- columns,
        into: MapSet.new(),
        do: column
  end
end
