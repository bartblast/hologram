defmodule Hologram.Migration.Value.SQL do
  @moduledoc false

  # Renders a resolved backfill to an SQL expression over the row aliased "$r0", through a mapping
  # of the schema at the op. It has its own walk rather than the query compiler's because it reads
  # a point in a migration's history, not the compiled entity modules. What each word means comes
  # from Hologram.DB.WordSQL.

  alias Hologram.DB.Codec
  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryCompiler
  alias Hologram.DB.WordSQL
  alias Hologram.Migration.Value.Resolver

  @plain_sql_types %{
    boolean: "boolean",
    date: "date",
    datetime: "timestamptz",
    float: "float8",
    integer: "int8",
    string: "text",
    time: "time",
    uuid: "uuid"
  }

  @doc """
  Returns the SQL expression of the given resolved backfill for the given target member of the
  given entity type, the joins it reads through, and the parameters it binds, in order. An enum of
  another attribute is cast to the target's type, since each enum attribute has a PostgreSQL type
  of its own.

  The rows pointing at this one are aggregated once and joined. A reference column has no index of
  its own, so a subquery per row would scan the related table once for each row.
  """
  @spec render(
          %{term: Resolver.resolved(), type: Resolver.type()},
          module,
          %{module => %{atom => any}},
          Resolver.target()
        ) :: {String.t(), String.t(), list}
  def render(%{term: term, type: type}, entity_type, mapping, target) do
    aggregates = aggregates(term)
    scope = %{aggregates: Map.new(aggregates), depth: 0, entity: entity_type, mapping: mapping}

    {sql, reversed_params} = term_sql(term, scope, [])
    joins = Enum.map_join(aggregates, " ", &join_sql(&1, scope))

    {cast_to_target(sql, type, entity_type, mapping, target), joins,
     Enum.reverse(reversed_params)}
  end

  @doc """
  Returns the statement writing the given rendered backfill into the given column of the given
  table. A backfill with joins reads the row through a self-join, since an `UPDATE` can't join its
  own target. With `nulls_only: true` it writes only the rows holding NULL, and with
  `returning: true` it returns the ids it wrote.
  """
  @spec fill_statement(String.t(), String.t(), {String.t(), String.t(), list}, keyword) ::
          String.t()
  def fill_statement(table, column, {fragment, joins, _params}, opts \\ []) do
    source = qualified_table(table)
    quoted = Mapper.quote_identifier(column)
    target = if joins == "", do: ~s("$r0"), else: ~s("$u")
    filter = if opts[:nulls_only], do: "#{target}.#{quoted} IS NULL"
    returning = if opts[:returning], do: ~s| RETURNING #{target}."id"|, else: ""

    update = ~s|UPDATE #{source} AS #{target} SET #{quoted} = #{fragment}|

    statement =
      if joins == "" do
        update <> if(filter, do: " WHERE #{filter}", else: "")
      else
        and_filter = if filter, do: " AND #{filter}", else: ""

        update <>
          ~s| FROM #{source} AS "$r0" #{joins} WHERE "$u"."id" = "$r0"."id"#{and_filter}|
      end

    statement <> returning
  end

  @doc """
  Returns the statement counting the keys of the given unique index columns that would repeat once
  the NULLs of the given column, one of them, take the given rendered expression and its joins,
  reading the row as "$r0". Only keys holding a row the fill writes count. Nulls in a key compare as values when
  nulls_distinct is false, matching the index.
  """
  @spec filled_repeat_statement(
          String.t(),
          list(String.t()),
          String.t(),
          boolean,
          String.t(),
          String.t()
        ) :: String.t()
  def filled_repeat_statement(table, columns, filled_column, nulls_distinct, fragment, joins) do
    keys =
      columns
      |> Enum.with_index()
      |> Enum.map(fn {column, index} ->
        read = ~s("$r0".#{Mapper.quote_identifier(column)})
        expression = if column == filled_column, do: "COALESCE(#{read}, #{fragment})", else: read

        {expression, ~s("$k#{index}")}
      end)

    selected = Enum.map_join(keys, ", ", fn {expression, key} -> "#{expression} AS #{key}" end)
    grouped = Enum.map_join(keys, ", ", &elem(&1, 1))

    not_null =
      if nulls_distinct do
        " WHERE " <>
          Enum.map_join(keys, " AND ", fn {_expression, key} -> "#{key} IS NOT NULL" end)
      else
        ""
      end

    filled = ~s("$r0".#{Mapper.quote_identifier(filled_column)} IS NULL)
    source = ~s("#{Mapper.data_schema()}".#{Mapper.quote_identifier(table)})

    ~s|SELECT COUNT(*) FROM (SELECT 1 FROM (SELECT #{selected}, #{filled} AS "$filled" | <>
      ~s|FROM #{source} AS "$r0" #{joins}) AS "$keys"#{not_null} GROUP BY #{grouped} | <>
      ~s|HAVING COUNT(*) > 1 AND COUNT(*) FILTER (WHERE "$filled") > 0) AS duplicates|
  end

  @doc """
  Returns what the given resolved backfill needs its enum types to accept, as pairs of a type name
  and a value: each literal, and every value of another attribute's enum it copies into the
  target's type. PostgreSQL refuses a value in the transaction that added it to its type.
  """
  @spec enum_uses(
          %{term: Resolver.resolved(), type: Resolver.type()},
          module,
          %{module => %{atom => any}},
          Resolver.target()
        ) :: list({String.t(), String.t()})
  def enum_uses(%{term: term, type: type}, entity_type, mapping, target) do
    literals =
      for {:value, value, {:enum, owner, name, _values}} <- subterms(term) do
        {attribute_column!(mapping, owner, name).sql_type, Codec.encode(value, :enum)}
      end

    literals ++ copied_enum_values(type, entity_type, mapping, target)
  end

  @doc """
  Returns the sort key columns the given resolved backfill orders by, in the form the companion
  fill takes.
  """
  @spec sort_keys(
          %{required(:term) => Resolver.resolved(), optional(atom) => any},
          module,
          %{module => %{atom => any}}
        ) :: list(%{op: :add_column, table: String.t(), column: String.t()})
  def sort_keys(%{term: term}, entity_type, mapping) do
    scope = %{depth: 0, entity: entity_type, mapping: mapping}

    for {:most_common, set, attribute, _type, _ranks} <- subterms(term),
        entry = set_entry(set, scope),
        sort_key = Enum.find(entry.columns, &(&1.source == {:sort_key, attribute})) do
      %{op: :add_column, table: entry.table, column: sort_key.name}
    end
  end

  # Each word over the rows pointing at this one, with the alias its join goes under.
  defp aggregates(term) do
    term
    |> subterms()
    |> Enum.filter(&referencing?/1)
    |> Enum.uniq()
    |> Enum.with_index()
    |> Enum.map(fn {aggregate, index} ->
      {aggregate, Mapper.quote_identifier("$a#{index}")}
    end)
  end

  defp attribute_column!(mapping, owner, name) do
    mapping
    |> Map.fetch!(owner)
    |> Map.fetch!(:columns)
    |> Enum.find(&(&1.source == {:attribute, name}))
  end

  defp cast_to_target(sql, {:enum, owner, name, _values}, entity_type, mapping, %{
         kind: :attribute,
         name: target_name,
         type: :enum
       })
       when {owner, name} != {entity_type, target_name} do
    "(#{sql})::text::#{enum_sql_type(mapping, entity_type, target_name)}"
  end

  defp cast_to_target(sql, _type, _entity_type, _mapping, _target), do: sql

  defp column_sql(scope, column) do
    "#{row_alias(scope)}.#{Mapper.quote_identifier(column.name)}"
  end

  defp copied_enum_values({:enum, owner, name, values}, entity_type, mapping, %{
         kind: :attribute,
         name: target_name,
         type: :enum
       })
       when {owner, name} != {entity_type, target_name} do
    target_sql_type = attribute_column!(mapping, entity_type, target_name).sql_type

    Enum.map(values, &{target_sql_type, Codec.encode(&1, :enum)})
  end

  defp copied_enum_values(_type, _entity_type, _mapping, _target), do: []

  defp encode_type({:enum, _owner, _name, _values}), do: :enum

  defp encode_type({:reference, _target}), do: :uuid

  defp encode_type(type), do: type

  defp enum_sql_type(mapping, owner, name) do
    column = attribute_column!(mapping, owner, name)

    "#{Mapper.quote_identifier(Mapper.data_schema())}.#{Mapper.quote_identifier(column.sql_type)}"
  end

  defp hop(name, scope) do
    entry = Map.fetch!(scope.mapping, scope.entity)
    reference = Enum.find(entry.columns, &(&1.source == {:relationship, name}))
    target_entity = related_entity!(scope.mapping, reference.references)

    {reference, %{scope | depth: scope.depth + 1, entity: target_entity}}
  end

  defp hop_subquery(inner_sql, reference, inner_scope, scope) do
    target_table = scope.mapping[inner_scope.entity].table

    "(SELECT #{inner_sql} FROM #{qualified_table(target_table)} AS #{row_alias(inner_scope)} " <>
      "WHERE #{row_alias(inner_scope)}.\"id\" = #{column_sql(scope, reference)})"
  end

  defp join_on(query, name) do
    ~s|LEFT JOIN (#{query}) AS #{name} ON #{name}.k = "$r0"."id"|
  end

  defp join_sql({{:count, {:referencing, type, ref}}, name}, scope) do
    {entry, key} = referencing_source(type, ref, scope)
    source = "FROM #{qualified_table(entry.table)} WHERE #{key} IS NOT NULL"

    join_on(WordSQL.count_by(key, source), name)
  end

  defp join_sql(
         {{:most_common, {:referencing, type, ref}, attribute, _kind, _ranks}, name},
         scope
       ) do
    {entry, key} = referencing_source(type, ref, scope)
    value = Mapper.quote_identifier(QueryCompiler.name_column(entry, attribute).name)

    sort_key =
      case Enum.find(entry.columns, &(&1.source == {:sort_key, attribute})) do
        nil -> nil
        column -> Mapper.quote_identifier(column.name)
      end

    source =
      "FROM #{qualified_table(entry.table)} WHERE #{key} IS NOT NULL AND #{value} IS NOT NULL"

    join_on(WordSQL.most_common_by(key, value, sort_key, source), name)
  end

  # The id of the row a set hangs off, and the entity type it's of, read through the given to-one
  # hops. The last hop's reference is that id, so it needs no read of the row it points at.
  defp owner_id([], scope), do: {"#{row_alias(scope)}.\"id\"", scope.entity}

  defp owner_id([hop], scope) do
    {reference, inner_scope} = hop(hop, scope)

    {column_sql(scope, reference), inner_scope.entity}
  end

  defp owner_id([hop | rest], scope) do
    {reference, inner_scope} = hop(hop, scope)
    {inner_sql, owner} = owner_id(rest, inner_scope)

    {hop_subquery(inner_sql, reference, inner_scope, scope), owner}
  end

  defp qualified_table(table) do
    "#{Mapper.quote_identifier(Mapper.data_schema())}.#{Mapper.quote_identifier(table)}"
  end

  defp referencing?({:count, {:referencing, _type, _ref}}), do: true

  defp referencing?({:most_common, {:referencing, _type, _ref}, _attribute, _kind, _ranks}) do
    true
  end

  defp referencing?(_term), do: false

  defp referencing_source(type, ref, scope) do
    entry = Map.fetch!(scope.mapping, type)
    column = Enum.find(entry.columns, &(&1.source == {:relationship, ref}))

    {entry, Mapper.quote_identifier(column.name)}
  end

  defp related_entity!(mapping, table) do
    {entity_type, _entry} = Enum.find(mapping, fn {_type, entry} -> entry.table == table end)

    entity_type
  end

  defp row_alias(%{depth: depth}), do: Mapper.quote_identifier("$r#{depth}")

  defp set_entry({:referencing, type, _ref}, scope), do: Map.fetch!(scope.mapping, type)

  defp set_entry({:relationship, path}, scope) do
    {_owner_id_sql, join_table} = set_source(path, scope)

    Map.fetch!(scope.mapping, related_entity!(scope.mapping, join_table.target_table))
  end

  defp set_source(path, scope) do
    {hops, [set_name]} = Enum.split(path, -1)
    {owner_id_sql, owner} = owner_id(hops, scope)

    join_table =
      scope.mapping
      |> Map.fetch!(owner)
      |> Map.fetch!(:join_tables)
      |> Enum.find(&(&1.relationship == set_name))

    {owner_id_sql, join_table}
  end

  defp slot(value, type, scope, reversed_params) do
    encoded = Codec.encode(value, encode_type(type))
    number = length(reversed_params) + 1

    {"$#{number}::#{sql_type(type, scope.mapping)}", [encoded | reversed_params]}
  end

  # A string orders by its sort key and then itself, the pair the query compiler orders by. Any
  # other value orders by itself, an enum in its type's declared order.
  defp sort_key_sql(entry, attribute, scope) do
    case Enum.find(entry.columns, &(&1.source == {:sort_key, attribute})) do
      nil -> nil
      sort_key -> column_sql(scope, sort_key)
    end
  end

  defp sql_type({:enum, owner, name, _values}, mapping), do: enum_sql_type(mapping, owner, name)

  defp sql_type({:reference, _target}, _mapping), do: "uuid"

  defp sql_type(type, _mapping), do: Map.fetch!(@plain_sql_types, type)

  defp subterms({:at, {:split, text, separator}, position} = term) do
    [term | Enum.flat_map([text, separator, position], &subterms/1)]
  end

  defp subterms({kind, terms} = term) when kind in [:coalesce, :concat] do
    [term | Enum.flat_map(terms, &subterms/1)]
  end

  defp subterms(term), do: [term]

  defp term_sql({:value, value, type}, scope, reversed_params) do
    slot(value, type, scope, reversed_params)
  end

  defp term_sql({:name, [name], _type}, scope, reversed_params) do
    entry = Map.fetch!(scope.mapping, scope.entity)

    {column_sql(scope, QueryCompiler.name_column(entry, name)), reversed_params}
  end

  # One scalar subquery per hop, each with an alias of its own, so a self-relationship reads
  # another row rather than itself. A nil reference finds no row, which reads as NULL.
  defp term_sql({:name, [hop | rest], type}, scope, reversed_params) do
    {reference, inner_scope} = hop(hop, scope)

    {inner_sql, new_params} = term_sql({:name, rest, type}, inner_scope, reversed_params)

    {hop_subquery(inner_sql, reference, inner_scope, scope), new_params}
  end

  defp term_sql({:concat, operands}, scope, reversed_params) do
    {operand_sqls, new_params} = terms_sql(operands, scope, reversed_params)

    {WordSQL.concat(operand_sqls), new_params}
  end

  defp term_sql(
         {:at, {:split, text, {:value, separator, :string}}, {:value, position, :integer}},
         scope,
         reversed_params
       ) do
    {text_sql, params_after_text} = term_sql(text, scope, reversed_params)
    {separator_sql, new_params} = slot(separator, :string, scope, params_after_text)

    {WordSQL.at_split(text_sql, separator_sql, position), new_params}
  end

  defp term_sql({:coalesce, values}, scope, reversed_params) do
    {value_sqls, new_params} = terms_sql(values, scope, reversed_params)

    {WordSQL.coalesce(value_sqls), new_params}
  end

  defp term_sql({:count, {:referencing, _type, _ref}} = term, scope, reversed_params) do
    {"COALESCE(#{Map.fetch!(scope.aggregates, term)}.v, 0)", reversed_params}
  end

  defp term_sql({:count, {:relationship, path}}, scope, reversed_params) do
    {owner_id_sql, join_table} = set_source(path, scope)
    join_alias = Mapper.quote_identifier("$j#{scope.depth + 1}")

    source =
      "FROM #{qualified_table(join_table.name)} AS #{join_alias} " <>
        "WHERE #{join_alias}.\"source_id\" = #{owner_id_sql}"

    {WordSQL.count(source), reversed_params}
  end

  defp term_sql(
         {:most_common, {:referencing, _type, _ref}, _attribute, _kind, _ranks} = term,
         scope,
         reversed_params
       ) do
    {"#{Map.fetch!(scope.aggregates, term)}.v", reversed_params}
  end

  defp term_sql(
         {:most_common, {:relationship, path}, attribute, _type, _ranks},
         scope,
         reversed_params
       ) do
    {owner_id_sql, join_table} = set_source(path, scope)
    target_entity = related_entity!(scope.mapping, join_table.target_table)
    target_entry = Map.fetch!(scope.mapping, target_entity)
    join_alias = Mapper.quote_identifier("$j#{scope.depth + 1}")
    row_scope = %{scope | depth: scope.depth + 1, entity: target_entity}
    value_sql = column_sql(row_scope, QueryCompiler.name_column(target_entry, attribute))

    row = row_alias(row_scope)

    source =
      ~s|FROM #{qualified_table(target_entry.table)} AS #{row} | <>
        ~s|JOIN #{qualified_table(join_table.name)} AS #{join_alias} | <>
        ~s|ON #{join_alias}."target_id" = #{row}."id" | <>
        ~s|WHERE #{join_alias}."source_id" = #{owner_id_sql}|

    sql =
      WordSQL.most_common(value_sql, sort_key_sql(target_entry, attribute, row_scope), source)

    {sql, reversed_params}
  end

  defp terms_sql(terms, scope, reversed_params) do
    Enum.map_reduce(terms, reversed_params, &term_sql(&1, scope, &2))
  end
end
