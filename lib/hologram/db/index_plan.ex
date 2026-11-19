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

  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Commons.SerializationUtils
  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryCompiler
  alias Hologram.Entity
  alias Hologram.Entity.Derived
  alias Hologram.Query
  alias Hologram.Query.Stage
  alias Hologram.Reflection

  # The most needs the ORs of one clause list may add between them. An OR that would take them
  # past it adds nothing, and is left to the conditions beside it: an index per arm costs every
  # write, and a statement with that many alternatives is better served by what's ANDed with them.
  @max_or_needs 8

  # PostgreSQL's limit on the columns of an index (INDEX_MAX_KEYS).
  @max_columns 32

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
  Returns the index plan of the lookups the framework itself makes over the tables of the given
  mapping - `select/2` over `framework_needs/1` - what every database the mapping describes
  carries whatever its queries read. Raises as `select/2` does.
  """
  @spec framework_plan(%{module => %{atom => any}}) :: %{String.t() => %{String.t() => map}}
  def framework_plan(mapping) do
    mapping
    |> framework_needs()
    |> select(mapping)
  end

  @doc """
  Returns the access needs of the lookups the framework itself makes, whatever the queries: each
  reference column, which a delete checks and the sync's backwards search and recheck follow from
  the row it names; each join table's reverse direction, from the target back to its sources, which
  its primary key - led by the source - can't serve; and the grant store's lookup of the grants on
  an entity, by type, then id, then role.
  """
  @spec framework_needs(%{module => %{atom => any}}) :: list(need)
  def framework_needs(mapping) do
    mapping
    |> Enum.sort()
    |> Enum.flat_map(fn {entity_type, entity_mapping} ->
      reference_needs =
        for %{references: references, name: name} <- entity_mapping.columns,
            references != nil,
            do: %{table: entity_mapping.table, eq: MapSet.new([name]), range: nil, order: []}

      reverse_needs =
        Enum.map(entity_mapping.join_tables, fn join_table ->
          %{
            table: join_table.name,
            eq: MapSet.new(["target_id"]),
            range: nil,
            order: ["source_id"]
          }
        end)

      reference_needs ++ reverse_needs ++ grant_store_needs(entity_type, entity_mapping)
    end)
  end

  @doc """
  Returns the path of the index needs dump the build writes (see
  `Hologram.Compiler.build_index_needs_plt/2`).
  """
  @spec dump_path() :: String.t()
  def dump_path do
    Path.join([Reflection.build_dir(), Reflection.index_needs_plt_dump_file_name()])
  end

  @doc """
  Returns the access needs in the index needs dump at the given path, or none when there is no
  dump, as for an app the Hologram compile never ran in.
  """
  @spec dumped_needs(String.t()) :: list(need)
  def dumped_needs(path \\ dump_path()) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> SerializationUtils.deserialize(true)
      |> Map.fetch!(:needs)
    else
      []
    end
  end

  @doc """
  Returns the names of the indexes of the given schema (see `Hologram.DB.Introspection.schema/0`)
  the index plan owns: the plain btree ones named `...$idx` that aren't unique. Introspection marks
  any other shape with `:non_plain`. One under another name is the drift check's.
  """
  @spec owned_index_names(%{atom => any}) :: MapSet.t(String.t())
  def owned_index_names(schema) do
    for {_table, definition} <- schema.tables,
        {name, index} <- definition.indexes,
        String.ends_with?(name, "$idx"),
        not index.unique,
        not Map.has_key?(index, :non_plain),
        into: MapSet.new(),
        do: name
  end

  @doc """
  Returns the index plan over the tables of the given mapping for what the server runs: the
  framework's own lookups and the needs the build derived from the queries (see `dumped_needs/1`).
  A dumped need naming a table or a column the mapping no longer holds is left out, as `select/2`
  leaves one out.
  """
  @spec plan(%{module => %{atom => any}}, String.t()) :: %{String.t() => %{String.t() => map}}
  def plan(mapping, dump_path \\ dump_path()) do
    mapping
    |> framework_needs()
    |> Enum.concat(dumped_needs(dump_path))
    |> select(mapping)
  end

  @doc """
  Returns the access needs of the statement the given normalized query term compiles to with the
  given policy (nil for a raw read, otherwise as `Hologram.DB.QueryCompiler.compile/3` takes it),
  against the given mapping - each a map with :table, :eq (the columns an equality or a
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

  The read rules a policy applies - for an anonymous session, the ones left once whatever names
  the acting user or a role is folded away - join the statement as one OR group, and their
  needs stand beside the filter's rather than crossed with them, since Postgres combines the two
  with a BitmapAnd. Each rule gives the needs its predicates give, as a filter would, when every
  rule has a predicate an index serves. A rule asking only for a role or a delegation, which are
  subqueries, leaves the group to be checked row by row, so then the rules give nothing, and so
  does a rule asking nothing, which drops the group. A rule that never holds - a delegation to a
  type granting nothing - is left out first, as the compiler leaves it out. The related tables a
  rule's predicates read give their needs as anywhere else, and those of the rules of the tables
  the statement reaches give none.
  """
  @spec needs(Query.t(), %{module => %{atom => any}}, %{atom => any} | nil) :: list(need)
  def needs(term, mapping, policy \\ nil) do
    term
    |> level_needs(nil, mapping)
    |> Enum.concat(deeper_needs(term, mapping))
    |> Enum.concat(rule_needs(term, mapping, policy))
    |> Enum.uniq()
  end

  @doc """
  Returns the indexes that serve the given access needs over the tables of the given mapping, as
  `%{table => %{name => %{columns:, nulls_distinct: true, unique: false}}}`, the shape
  `Hologram.DB.Schema` holds indexes in - the same plan whatever order the needs come in.

  An index serves a need when its first columns are the need's equality columns in any order,
  followed by its range column, then by its order columns. The primary key and the model's unique
  indexes count, so a need they serve adds nothing. The others are merged into as few indexes as
  serve them all, greedily: taken from the fewest equality columns up, a need extends an index
  whose columns are all among its equality columns, with the rest of them sorted by name, then its
  range and order columns - the largest such index, the first created among equals - and otherwise
  starts one of its own. An index whose columns lead another's
  is dropped, the longer one serving all it does. A need naming a table or a column the mapping
  doesn't hold is left out, since a live reload reconciles the model before the build writes fresh
  needs, and so is one naming a raw string column: no plan index ever holds one.

  Each index is named `<table segments>_<columns>_$idx`, fitted the way every derived name is (see
  `Hologram.DB.Mapper.fit_identifier/3`). Of two indexes of one table deriving one name, the first by
  its columns keeps it and each other one carries a 4-byte digest of its columns after them. Raises
  Hologram.CompileError when indexes of two tables derive the same name.
  """
  @spec select(list(need), %{module => %{atom => any}}) :: %{String.t() => %{String.t() => map}}
  def select(needs, mapping) do
    tables = table_directory(mapping)

    indexes =
      needs
      |> Enum.filter(&known_need?(&1, tables))
      |> Enum.uniq()
      |> Enum.group_by(& &1.table)
      |> Enum.sort()
      |> Enum.flat_map(fn {table, table_needs} ->
        table_info = Map.fetch!(tables, table)

        table_needs
        |> Enum.sort_by(&need_rank/1)
        |> Enum.reduce([], &place_need(&1, &2, table_info.keys))
        |> Enum.reverse()
        |> Enum.map(&within_column_limit/1)
        |> Enum.uniq()
        |> without_prefixes()
        |> Enum.map(& &1.columns)
        |> name_indexes(table, table_info)
      end)

    validate_names!(indexes)

    Enum.reduce(indexes, %{}, fn {table, name, columns, _declaration}, acc ->
      definition = %{columns: columns, nulls_distinct: true, unique: false}
      Map.update(acc, table, %{name => definition}, &Map.put(&1, name, definition))
    end)
  end

  # The read rules join the statement as one OR group of their alternatives, ANDed with the filter -
  # or, when one rule is left, as that rule's conditions ANDed with it. Postgres combines the two
  # with a BitmapAnd, so the rules' needs stand beside the filter's rather than crossed with them -
  # crossing them would make filters times rules indexes. The group is answered from indexes only
  # when every rule has a condition an index serves: a grant and a delegation are subqueries, which
  # none does, so a rule asking only those leaves the group to be checked row by row, and the rules
  # add nothing. A rule that never holds - a delegation to a type granting nothing - leaves the
  # group, as the compiler leaves it out. A rule asking nothing drops the group and every condition
  # its rules ask, and rules nobody can satisfy make the statement read no rows, so both need
  # nothing. What the rules read of related tables - their quantifiers, the derived fields they read
  # - is needed as any condition's is, a lone rule's ANDed at the top of the statement.
  defp rule_needs(_term, _mapping, nil), do: []

  defp rule_needs(term, mapping, policy) do
    rules =
      policy.rules
      |> QueryCompiler.applicable_rules(policy)
      |> Enum.reject(&QueryCompiler.never_rule?(term.entity, &1, policy))

    unconditional? = Enum.any?(rules, &(&1.predicates == [] and &1.to == nil and &1.via == nil))

    if unconditional? or rules == [] do
      []
    else
      group_needs(term, rules, mapping) ++ rules_deeper_needs(term.entity, rules, mapping)
    end
  end

  defp group_needs(term, rules, mapping) do
    if Enum.all?(rules, &servable_rule?(&1, term.entity, mapping)) do
      Enum.flat_map(rules, fn rule ->
        rule_term = %{term | filter: rule.predicates, sort: [], take: nil, cardinality: :set}

        level_needs(rule_term, nil, mapping)
      end)
    else
      []
    end
  end

  defp rules_deeper_needs(entity_type, rules, mapping) do
    context = %{mapping: mapping, outer: []}
    top? = match?([_rule], rules)

    Enum.flat_map(rules, &clause_level_needs(&1.predicates, entity_type, top?, context))
  end

  defp servable_rule?(rule, entity_type, mapping) do
    entity_mapping = Map.fetch!(mapping, entity_type)
    scope = level_scope(entity_mapping, false)

    rule.predicates
    |> paths(scope)
    |> Enum.any?(&(&1 != []))
  end

  # The needs of one level of a statement - the queried row's, or a related table's a subquery
  # reads, matched to the row above by the given reference column (nil at the top), which an index
  # holds as a column an equality fixes: each probe of the subquery compares it with the row above's
  # id.
  defp level_needs(term, link, mapping) do
    entity_mapping = Map.fetch!(mapping, term.entity)
    scope = level_scope(entity_mapping, link != nil)

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

  # The tables of the mapping by name: each entity table and join table, with the segments its
  # names are fitted from, its columns, the column lists of the indexes the model gives it - its
  # primary key and its unique indexes - and what a collision report names it by.
  defp table_directory(mapping) do
    Enum.reduce(mapping, %{}, fn {entity_type, entity_mapping}, acc ->
      segments = Mapper.table_segments(entity_type)

      keys = [
        ["id"]
        | for({_name, %{unique: true, columns: columns}} <- entity_mapping.indexes, do: columns)
      ]

      raw_strings =
        for %{type: :string, source: {:attribute, _name}, name: name} <- entity_mapping.columns,
            into: MapSet.new(),
            do: name

      entity_entry = %{
        columns: MapSet.new(entity_mapping.columns, & &1.name),
        raw_strings: raw_strings,
        declaration: "an index on #{inspect(entity_type)}",
        keys: keys,
        segments: segments
      }

      join_entries =
        Map.new(
          entity_mapping.join_tables,
          &{&1.name, join_table_entry(&1, entity_type, segments)}
        )

      acc
      |> Map.put(entity_mapping.table, entity_entry)
      |> Map.merge(join_entries)
    end)
  end

  defp join_table_entry(join_table, entity_type, segments) do
    %{
      columns: MapSet.new(["source_id", "target_id"]),
      raw_strings: MapSet.new(),
      declaration: "relationship #{inspect(join_table.relationship)} in #{inspect(entity_type)}",
      keys: [["source_id", "target_id"]],
      segments: Enum.concat(segments, ["#{join_table.relationship}_$join"])
    }
  end

  # A need naming a column the table doesn't hold is stale: a live reload reconciles the model
  # before the build writes fresh needs. So is one naming a raw string: the needs name one only
  # when a unique index serves them, which bounds it to what fits that index alone, so a need a
  # model change left behind must never build an index over it.
  defp known_need?(need, tables) do
    case Map.fetch(tables, need.table) do
      {:ok, %{columns: columns, raw_strings: raw_strings}} ->
        need
        |> need_columns()
        |> Enum.all?(&(MapSet.member?(columns, &1) and not MapSet.member?(raw_strings, &1)))

      :error ->
        false
    end
  end

  defp need_columns(need), do: MapSet.to_list(need.eq) ++ List.wrap(need.range) ++ need.order

  # By the fewest equality columns first, since an index can grow from them to serve more - the
  # rest of the rank only makes it a total order, so the plan never depends on the needs' order.
  defp need_rank(need),
    do: {MapSet.size(need.eq), Enum.sort(need.eq), need.range || "", need.order}

  # Places a need into the indexes chosen so far, newest first: served by a key or a chosen index,
  # extending the largest chosen index it can, or as an index of its own.
  defp place_need(need, chosen, keys) do
    cond do
      Enum.any?(keys, &serves?(&1, need)) or Enum.any?(chosen, &serves?(&1.columns, need)) ->
        chosen

      extended = extension_target(need, chosen) ->
        Enum.map(chosen, &extended_if(&1, extended, need))

      true ->
        [extend(%{columns: []}, need) | chosen]
    end
  end

  # PostgreSQL builds an index of at most 32 columns and refuses a wider one, which would then fail
  # every build. An index's leading columns serve what the whole would, as far as they go, so a
  # wider one keeps its first 32 - only a query naming that many columns at once gets there.
  defp within_column_limit(index), do: %{index | columns: Enum.take(index.columns, @max_columns)}

  # An index whose columns lead another's serves nothing the longer one doesn't, since a need reads
  # only an index's leading columns - as when two needs fix the same columns and their orders nest.
  defp without_prefixes(indexes) do
    Enum.reject(indexes, fn index ->
      Enum.any?(indexes, fn other ->
        length(other.columns) > length(index.columns) and
          List.starts_with?(other.columns, index.columns)
      end)
    end)
  end

  defp extended_if(index, index, need), do: extend(index, need)

  defp extended_if(index, _extended, _need), do: index

  defp extension_target(need, chosen) do
    chosen
    |> Enum.reverse()
    |> Enum.filter(&Enum.all?(&1.columns, fn column -> MapSet.member?(need.eq, column) end))
    |> Enum.max_by(&length(&1.columns), fn -> nil end)
  end

  defp extend(index, need) do
    added_eq =
      need.eq
      |> MapSet.difference(MapSet.new(index.columns))
      |> Enum.sort()

    %{columns: index.columns ++ added_eq ++ List.wrap(need.range) ++ need.order}
  end

  # An index serves a need when it leads with the need's equality columns, in any order, then holds
  # its range column, then its order columns.
  defp serves?(columns, need) do
    eq_size = MapSet.size(need.eq)
    {lead, rest} = Enum.split(columns, eq_size)

    MapSet.new(lead) == need.eq and length(lead) == eq_size and
      List.starts_with?(rest, List.wrap(need.range) ++ need.order)
  end

  defp collision_declarations(group) do
    group
    |> Enum.map(fn {_table, _name, _columns, declaration} -> declaration end)
    |> Enum.sort()
    |> Enum.join(", ")
  end

  # The grant store's reads that carry no user - the type-wide and entity grant checks, and the sync
  # recheck asking of every row a change touches - all fix the type first, then the id, then the
  # role, so its need pins that order: an app's read of the store by a prefix of it shares the index,
  # and the index keeps its name whatever else the app reads there.
  defp grant_store_needs(Hologram.Auth.RoleGrant, entity_mapping) do
    [
      %{
        table: entity_mapping.table,
        eq: MapSet.new(["entity_type"]),
        range: nil,
        order: ["entity_id", "role"]
      }
    ]
  end

  defp grant_store_needs(_entity_type, _entity_mapping), do: []

  # Columns join their names with `_`, so two indexes of one table can derive one name -
  # `["public", "id"]` and `["public_id"]`. Nobody declared either, so there is nothing to rename:
  # the first by its columns keeps the name, and each other one carries a digest of its columns.
  # A name an index of another table derives stays a collision (see validate_names!/1).
  defp name_indexes(column_lists, table, table_info) do
    column_lists
    |> Enum.group_by(&Mapper.fit_identifier(table_info.segments, &1, "$idx"))
    |> Enum.sort()
    |> Enum.flat_map(fn {name, columns_group} ->
      [first | rest] = Enum.sort(columns_group)

      [{name, first} | Enum.map(rest, &{digested_name(&1, table_info), &1})]
    end)
    |> Enum.map(fn {name, columns} ->
      declaration = "#{table_info.declaration} by #{Enum.join(columns, ", ")}"

      {table, name, columns, declaration}
    end)
  end

  defp digested_name(columns, table_info) do
    digest =
      columns
      |> Enum.join(",")
      |> CryptographicUtils.short_digest(4)

    Mapper.fit_identifier(table_info.segments, Enum.concat(columns, [digest]), "$idx")
  end

  # Index names live in one namespace per schema, across tables. A plan index ends in `$idx`, which
  # no primary key (`$pk`) or unique index (`$uidx`) does, so it can only collide with another plan
  # index - two tables whose segments and columns join to the same name.
  defp validate_names!(indexes) do
    collisions =
      indexes
      |> Enum.group_by(fn {_table, name, _columns, _declaration} -> name end)
      |> Enum.filter(fn {_name, group} -> length(group) > 1 end)
      |> Enum.sort()

    if collisions != [] do
      descriptions =
        Enum.map_join(collisions, "\n", fn {name, group} ->
          "  * index \"#{name}\" is derived from #{collision_declarations(group)}"
        end)

      raise Hologram.CompileError,
        message:
          "colliding derived names - rename the declarations so that every derived name is unique:\n#{descriptions}"
    end

    :ok
  end

  defp level_scope(entity_mapping, linked?) do
    unique_columns = unique_columns(entity_mapping)

    %{
      entity_mapping: entity_mapping,
      leading_unique_columns: leading_unique_columns(entity_mapping),
      linked?: linked?,
      raw_keys: raw_keys(entity_mapping, unique_columns),
      unique_columns: unique_columns
    }
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
    column = QueryCompiler.name_column(scope.entity_mapping, name)

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
    case QueryCompiler.name_column(scope.entity_mapping, name) do
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
    QueryCompiler.name_column(scope.entity_mapping, name)
  end

  defp order_column(_name, _scope), do: nil

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
