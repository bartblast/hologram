defmodule Hologram.DB.DDL do
  @moduledoc false

  alias Hologram.DB.Mapper

  # Types the mapper emits by name - anything else is a derived enum type, which lives
  # in the data schema and must be schema-qualified and quoted.
  @builtin_types ["boolean", "date", "float8", "int8", "text", "timestamptz", "uuid"]

  # Casts that succeed exactly when the existing rows allow them - each has a pre-flight
  # check statement counting the rows that cannot follow.
  @data_dependent_casts [
    {"float8", "int8"},
    {"text", "float8"},
    {"text", "int8"},
    {"timestamptz", "date"}
  ]

  @data_schema "hologram_data"

  # float8's magnitude bounds. A value between them converts - one outside overflows at the
  # top or underflows to zero at the bottom, and PostgreSQL refuses both.
  @float8_max_magnitude "1.7976931348623157e308"

  @float8_min_magnitude "4.9406564584124654e-324"

  # The longest text the range comparison will parse. It casts through numeric, which
  # refuses past 131072 integer or 16383 fractional digits - while the widest float8
  # written out in full decimal is about 1080 characters, the smallest denormal. Any limit
  # between the two can only refuse values no float8 could hold, and can never let the
  # comparison raise; 2000 is that policy choice.
  @float8_text_length_limit 2000

  # int8's bounds, and the first value above them. int8's max is not representable as a
  # float8 - it rounds UP to 2^63 - so a float8 comparison has to refuse from 2^63
  # inclusive, while a numeric comparison can use the max itself.
  @int8_max "9223372036854775807"

  @int8_min "-9223372036854775808"

  @int8_overflow_bound "9223372036854775808"

  # Casts that always succeed with no data loss (anything to text is handled separately -
  # text is the universal sink, derived enum types included).
  @safe_casts [{"date", "timestamptz"}, {"int8", "float8"}]

  @doc """
  Returns the pre-flight check statement for a data-dependent cast - a query counting
  the rows whose values cannot follow the type change from the given type to the given
  type. Only defined for type pairs classified :data_dependent by cast_class/2.

  Total in one direction, which is the property the applier's promise rests on: every row
  a statement passes converts without error. A statement may still refuse a row the cast
  would have taken - each mirrors PostgreSQL's rules rather than calling them, and every
  approximation errs towards refusing. Rows the cast would ROUND rather than refuse are
  counted too, since a conversion that silently loses data is not one to apply unasked.
  """
  @spec cast_check_statement(String.t(), String.t(), String.t(), String.t()) :: String.t()
  # A fraction is data the cast would round away, and the range is data it refuses
  # outright. NaN and the infinities need no branch of their own: PostgreSQL orders NaN
  # above every number and the infinities beyond both bounds, so the comparisons catch all
  # three - which they must, because NaN equals its own trunc and the fraction test alone
  # would let it through.
  def cast_check_statement(table, column, "float8", "int8") do
    quoted_column = Mapper.quote_identifier(column)

    count_statement(
      table,
      "#{quoted_column} <> trunc(#{quoted_column}) " <>
        "OR #{quoted_column} >= #{@int8_overflow_bound}::float8 " <>
        "OR #{quoted_column} < #{@int8_min}::float8"
    )
  end

  # Mirrors PostgreSQL's float8 input rules: surrounding whitespace, optional exponent,
  # bare-dot forms (5. and .5), and the case-insensitive specials NaN/Infinity/inf. Syntax
  # is half of what the cast enforces - float8 also has a RANGE at both ends, so a value
  # that reads as a number can still overflow it ('1e400') or underflow to zero ('1e-400').
  #
  # The guards ahead of the range comparison keep it from raising on input numeric itself
  # cannot hold: a mantissa longer than the length limit, or an exponent of four digits or
  # more, which reaches numeric's ceiling from a short string. Zero is answered before
  # both, because any exponent is legal on it.
  #
  # Conservative approximation, always towards refusing - hex floats, values within a
  # rounding step of the extremes, and a padded mantissa past the length limit are refused
  # although PostgreSQL would take them. The error's ways out cover them.
  # TODO: replace the syntax and range branches with pg_input_is_valid(<column>, 'float8')
  # once the minimum supported PostgreSQL version is 16 - it decides both in one call. The
  # zero and specials branches stay: validity is not the whole question, range is.
  def cast_check_statement(table, column, "text", "float8") do
    quoted_column = Mapper.quote_identifier(column)

    numeric_regex = "'^\\s*[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?\\s*$'"
    special_regex = "'^\\s*[+-]?(inf(inity)?|nan)\\s*$'"
    zero_regex = "'^\\s*[+-]?(0+(\\.0*)?|\\.0+)([eE][+-]?[0-9]+)?\\s*$'"
    long_exponent_regex = "'[eE][+-]?[0-9]{4,}\\s*$'"
    magnitude = "abs(#{quoted_column}::numeric)"

    count_statement(
      table,
      "CASE WHEN #{quoted_column} ~* #{special_regex} THEN false " <>
        "WHEN NOT (#{quoted_column} ~ #{numeric_regex}) THEN true " <>
        "WHEN #{quoted_column} ~ #{zero_regex} THEN false " <>
        "WHEN length(#{quoted_column}) > #{@float8_text_length_limit} THEN true " <>
        "WHEN #{quoted_column} ~ #{long_exponent_regex} THEN true " <>
        "ELSE #{magnitude} > #{@float8_max_magnitude} " <>
        "OR #{magnitude} < #{@float8_min_magnitude} END"
    )
  end

  # Mirrors PostgreSQL's int8 input rules: surrounding whitespace is accepted. int8 also
  # has a RANGE, so reading as an integer is not enough - '99999999999999999999' is all
  # digits and overflows. The digit-count branch is exact rather than approximate: past
  # leading zeros, twenty SIGNIFICANT digits is already one more than int8's nineteen, so
  # it refuses only what the range would, and it keeps the comparison below from meeting a
  # digit string longer than numeric can hold. The leading [1-9] is what makes "significant"
  # true - without it the trailing count can backtrack into the zeros it just skipped, and
  # a zero-padded small number reads as a long one.
  # TODO: replace the syntax and range branches with pg_input_is_valid(<column>, 'int8')
  # once the minimum supported PostgreSQL version is 16 - it decides both in one call.
  def cast_check_statement(table, column, "text", "int8") do
    quoted_column = Mapper.quote_identifier(column)

    syntax_regex = "'^\\s*[+-]?[0-9]+\\s*$'"
    long_regex = "'^\\s*[+-]?0*[1-9][0-9]{19,}\\s*$'"

    count_statement(
      table,
      "CASE WHEN NOT (#{quoted_column} ~ #{syntax_regex}) THEN true " <>
        "WHEN #{quoted_column} ~ #{long_regex} THEN true " <>
        "ELSE #{quoted_column}::numeric NOT BETWEEN #{@int8_min} AND #{@int8_max} END"
    )
  end

  def cast_check_statement(table, column, "timestamptz", "date") do
    quoted_column = Mapper.quote_identifier(column)

    count_statement(table, "#{quoted_column} <> date_trunc('day', #{quoted_column})")
  end

  @doc """
  Returns the cast class for a column type change: :safe (always succeeds, rendered as
  a plain USING cast), :data_dependent (succeeds exactly when the existing rows allow
  it - pre-flight checked via cast_check_statement/4), or :unsupported (no automatic
  conversion exists - the change requires removing and re-adding the attribute).
  Identity and anything-to-text are safe - text is the universal sink, derived enum
  types included.
  """
  @spec cast_class(String.t(), String.t()) :: :safe | :data_dependent | :unsupported
  def cast_class(type, type), do: :safe

  def cast_class(_from_type, "text"), do: :safe

  def cast_class(from_type, to_type) do
    cond do
      {from_type, to_type} in @safe_casts -> :safe
      {from_type, to_type} in @data_dependent_casts -> :data_dependent
      true -> :unsupported
    end
  end

  @doc """
  Returns the pre-flight check statement counting the rows that hold any of the given
  enum values in the given column - the values a rebuild would leave unrepresentable.
  """
  @spec enum_values_check_statement(String.t(), String.t(), list(String.t())) :: String.t()
  def enum_values_check_statement(table, column, values) do
    literals = Enum.map_join(values, ", ", &literal/1)

    count_statement(table, "#{Mapper.quote_identifier(column)}::text IN (#{literals})")
  end

  @doc """
  Returns the parameterized statement filling the NULLs of the given column with the
  first parameter.
  """
  @spec fill_statement(String.t(), String.t()) :: String.t()
  def fill_statement(table, column) do
    quoted_column = Mapper.quote_identifier(column)

    "UPDATE #{qualified(table)} SET #{quoted_column} = $1 WHERE #{quoted_column} IS NULL"
  end

  @doc """
  Returns the pre-flight check statement counting the rows with a NULL in the given
  column - the rows that block making the column required without a fill.
  """
  @spec null_check_statement(String.t(), String.t()) :: String.t()
  def null_check_statement(table, column) do
    count_statement(table, "#{Mapper.quote_identifier(column)} IS NULL")
  end

  @doc """
  Returns the pre-flight check statement counting the key groups of the given table's
  columns that hold more than one row - the duplicates that block a unique index build.

  Nulls compare as values when nulls_distinct is false, matching the index being built.
  """
  @spec duplicate_check_statement(String.t(), list(String.t()), boolean) :: String.t()
  def duplicate_check_statement(table, columns, nulls_distinct) do
    quoted_columns = Enum.map(columns, &Mapper.quote_identifier/1)
    grouped = Enum.join(quoted_columns, ", ")

    not_null_part =
      if nulls_distinct do
        " WHERE " <> Enum.map_join(quoted_columns, " AND ", &"#{&1} IS NOT NULL")
      else
        ""
      end

    "SELECT COUNT(*) FROM (SELECT 1 FROM #{qualified(table)}#{not_null_part} " <>
      "GROUP BY #{grouped} HAVING COUNT(*) > 1) AS duplicates"
  end

  @doc """
  Returns the check statement counting the VALID indexes carrying the given name - the ones
  already built and in use, which a build asked for again has nothing left to do about.
  """
  @spec built_index_check_statement(String.t()) :: String.t()
  def built_index_check_statement(index) do
    """
    SELECT COUNT(*)
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class c ON c.oid = i.indexrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = '#{@data_schema}' AND c.relname = #{literal(index)} AND i.indisvalid = TRUE\
    """
  end

  @doc """
  Returns the check statement counting the invalid indexes carrying the given name - the
  leftovers of a concurrent build that failed partway.

  A concurrent build spans several internal transactions, so PostgreSQL cannot roll one
  back: the failed index stays in the catalog flagged invalid, unused by queries and
  maintained by every write, holding its derived name.
  """
  @spec invalid_index_check_statement(String.t()) :: String.t()
  def invalid_index_check_statement(index) do
    """
    SELECT COUNT(*)
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class c ON c.oid = i.indexrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = '#{@data_schema}' AND c.relname = #{literal(index)} AND i.indisvalid = FALSE\
    """
  end

  @doc """
  Returns the statement listing the names of the invalid indexes of the data schema.

  A concurrent build that failed partway leaves its index in the catalog flagged
  invalid: it holds the derived name, serves no query, and every write maintains it.
  """
  @spec invalid_indexes_statement() :: String.t()
  def invalid_indexes_statement do
    """
    SELECT ic.relname
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ic ON ic.oid = i.indexrelid
    JOIN pg_catalog.pg_class c ON c.oid = i.indrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = '#{@data_schema}' AND NOT i.indisvalid\
    """
  end

  @doc """
  Returns the statement rebuilding the given index in place, concurrently.

  Rebuilding is what clears an invalid index: it replaces the failed build without
  taking the table's writes offline, and without the index ever being absent - which a
  drop-and-recreate pair could not promise if the node died between the two.

  Runs on a connection with no open transaction, as every concurrent operation must -
  PostgreSQL rejects one inside a transaction with 25001. The repair holds a
  session-scoped lock rather than a transactional one for exactly this reason.
  """
  @spec reindex_statement(String.t()) :: String.t()
  def reindex_statement(index) do
    ~s(REINDEX INDEX CONCURRENTLY "#{@data_schema}".#{Mapper.quote_identifier(index)})
  end

  @doc """
  Returns the pre-flight check statement counting the rows of the given table - the
  rows that block adding a required column without a fill.
  """
  @spec rows_check_statement(String.t()) :: String.t()
  def rows_check_statement(table) do
    "SELECT COUNT(*) FROM #{qualified(table)}"
  end

  @doc """
  Returns the DDL statements that execute the given change op, in execution order.

  :create_table renders one statement with all columns and the named primary key
  constraint - columns are laid out in canonical order (id first, created_at and
  updated_at last, everything else alphabetical). :add_column, :drop_column, and
  :drop_table render one statement each. :alter_column renders one ALTER TABLE
  statement combining a type action (with COLLATE and a USING cast) and a nullability
  action, as needed.

  :add_foreign_key renders a named ADD CONSTRAINT referencing the target table's id
  column with the delete action - :drop_foreign_key and :rename_constraint render
  their ALTER TABLE forms. :create_index renders a named index over its columns -
  :drop_index renders the schema-qualified drop (indexes are schema-level objects).

  The rename ops - :rename_table, :rename_column, :rename_index, :rename_enum_type -
  render their one-statement forms, and :widen_to_many moves the reference values of a
  relationship that became to-many into its new join table. They come from the migration
  applier only: a name-keyed diff cannot detect a rename or a cardinality change, so
  schema reconciliation never emits them, while a migration log carries the confirmed
  intent.

  :delete_role_grants empties the role grant store, the second op that touches rows
  rather than the schema. It too comes from the applier only, and for a stronger reason:
  the migration file has to SAY it deletes the grants, so the destruction is reviewed
  rather than inferred from a designation change.

  :create_enum_type, :drop_enum_type, :add_enum_value (with its BEFORE anchor when
  positioned), and :rename_enum_value render one statement each. :rebuild_enum_type
  renders the rebuild sequence: rename the old type aside, create the replacement
  under the canonical name, cast every column using the type (through text, applying
  the optional value remap as a searched CASE expression), then drop the old type. A
  remap entry carries :from, :to, and :scope - nil to remap the value wherever it
  stands, or {column, value} to remap it only in the rows where that other column holds
  that value.
  """
  @spec statements(%{atom => any}) :: list(String.t())
  def statements(%{op: :add_column} = op) do
    [
      "ALTER TABLE #{qualified(op.table)} " <>
        "ADD COLUMN #{column_definition(op.column, op.definition)}"
    ]
  end

  def statements(%{op: :add_enum_value} = op) do
    position_part =
      case op.position do
        {:before, anchor} -> " BEFORE #{literal(anchor)}"
        nil -> ""
      end

    [
      "ALTER TYPE #{qualified(op.enum_type)} " <>
        "ADD VALUE #{literal(op.value)}#{position_part}"
    ]
  end

  def statements(%{op: :add_foreign_key} = op) do
    [
      "ALTER TABLE #{qualified(op.table)} " <>
        "ADD CONSTRAINT #{Mapper.quote_identifier(op.constraint)} " <>
        "FOREIGN KEY (#{Mapper.quote_identifier(op.column)}) " <>
        ~s{REFERENCES #{qualified(op.references)} ("id") } <>
        "ON DELETE #{delete_action(op.on_delete)}"
    ]
  end

  def statements(%{op: :alter_column} = op) do
    type_actions =
      if op.before.type != op.after.type or op.before.collation != op.after.collation do
        column = Mapper.quote_identifier(op.column)
        type = column_type(op.after)

        ["ALTER COLUMN #{column} TYPE #{type} USING #{column}::#{type_sql(op.after.type)}"]
      else
        []
      end

    null_actions =
      case {op.before.null, op.after.null} do
        {same_null, same_null} -> []
        {false, true} -> ["ALTER COLUMN #{Mapper.quote_identifier(op.column)} DROP NOT NULL"]
        {true, false} -> ["ALTER COLUMN #{Mapper.quote_identifier(op.column)} SET NOT NULL"]
      end

    actions = Enum.join(type_actions ++ null_actions, ", ")

    ["ALTER TABLE #{qualified(op.table)} #{actions}"]
  end

  def statements(%{op: :create_enum_type} = op) do
    values = Enum.map_join(op.values, ", ", &literal/1)

    ["CREATE TYPE #{qualified(op.enum_type)} AS ENUM (#{values})"]
  end

  # A `concurrently: true` op must reach the database on a connection with no open
  # transaction - PostgreSQL rejects a concurrent build inside one with 25001. That is why
  # such ops are split into the applier's tail and run after their file commits, rather
  # than being a property of the statement itself.
  def statements(%{op: :create_index} = op) do
    columns = Enum.map_join(op.columns, ", ", &Mapper.quote_identifier/1)
    unique_sql = if op.unique, do: "UNIQUE ", else: ""
    nulls_sql = if op.nulls_distinct, do: "", else: " NULLS NOT DISTINCT"
    concurrently_sql = if op[:concurrently], do: "CONCURRENTLY ", else: ""

    [
      "CREATE #{unique_sql}INDEX #{concurrently_sql}#{Mapper.quote_identifier(op.index)} " <>
        "ON #{qualified(op.table)} (#{columns})#{nulls_sql}"
    ]
  end

  def statements(%{op: :create_table} = op) do
    column_lines =
      op.columns
      |> Map.keys()
      |> Enum.sort_by(&column_order_key/1)
      |> Enum.map(&"  #{column_definition(&1, op.columns[&1])}")

    pk_columns = Enum.map_join(op.primary_key.columns, ", ", &Mapper.quote_identifier/1)

    pk_line =
      "  CONSTRAINT #{Mapper.quote_identifier(op.primary_key.constraint)} " <>
        "PRIMARY KEY (#{pk_columns})"

    lines = Enum.join(column_lines, ",\n") <> ",\n" <> pk_line

    ["CREATE TABLE #{qualified(op.table)} (\n#{lines}\n)"]
  end

  def statements(%{op: :delete_role_grants} = op) do
    ["DELETE FROM #{qualified(op.table)}"]
  end

  def statements(%{op: :drop_column} = op) do
    ["ALTER TABLE #{qualified(op.table)} DROP COLUMN #{Mapper.quote_identifier(op.column)}"]
  end

  def statements(%{op: :drop_enum_type} = op) do
    ["DROP TYPE #{qualified(op.enum_type)}"]
  end

  def statements(%{op: :drop_foreign_key} = op) do
    [
      "ALTER TABLE #{qualified(op.table)} " <>
        "DROP CONSTRAINT #{Mapper.quote_identifier(op.constraint)}"
    ]
  end

  def statements(%{op: :drop_index} = op) do
    ["DROP INDEX #{qualified(op.index)}"]
  end

  def statements(%{op: :drop_table} = op) do
    ["DROP TABLE #{qualified(op.table)}"]
  end

  def statements(%{op: :rebuild_enum_type} = op) do
    old_type = Mapper.fit_identifier("#{op.enum_type}_$old")
    remap = Map.get(op, :remap, [])

    rename_statement =
      "ALTER TYPE #{qualified(op.enum_type)} RENAME TO #{Mapper.quote_identifier(old_type)}"

    create_statement =
      "CREATE TYPE #{qualified(op.enum_type)} AS ENUM " <>
        "(#{Enum.map_join(op.values, ", ", &literal/1)})"

    cast_statements =
      Enum.map(op.columns, fn {table, column} ->
        quoted_column = Mapper.quote_identifier(column)
        type = qualified(op.enum_type)

        "ALTER TABLE #{qualified(table)} " <>
          "ALTER COLUMN #{quoted_column} TYPE #{type} " <>
          "USING #{rebuild_cast(quoted_column, remap)}::#{type}"
      end)

    drop_statement = "DROP TYPE #{qualified(old_type)}"

    Enum.concat([[rename_statement, create_statement], cast_statements, [drop_statement]])
  end

  def statements(%{op: :rename_constraint} = op) do
    [
      "ALTER TABLE #{qualified(op.table)} " <>
        "RENAME CONSTRAINT #{Mapper.quote_identifier(op.from)} " <>
        "TO #{Mapper.quote_identifier(op.to)}"
    ]
  end

  def statements(%{op: :rename_column} = op) do
    [
      "ALTER TABLE #{qualified(op.table)} " <>
        "RENAME COLUMN #{Mapper.quote_identifier(op.from)} " <>
        "TO #{Mapper.quote_identifier(op.to)}"
    ]
  end

  def statements(%{op: :rename_enum_type} = op) do
    ["ALTER TYPE #{qualified(op.from)} RENAME TO #{Mapper.quote_identifier(op.to)}"]
  end

  def statements(%{op: :rename_enum_value} = op) do
    [
      "ALTER TYPE #{qualified(op.enum_type)} " <>
        "RENAME VALUE #{literal(op.from)} TO #{literal(op.to)}"
    ]
  end

  def statements(%{op: :rename_index} = op) do
    ["ALTER INDEX #{qualified(op.from)} RENAME TO #{Mapper.quote_identifier(op.to)}"]
  end

  def statements(%{op: :rename_table} = op) do
    ["ALTER TABLE #{qualified(op.from)} RENAME TO #{Mapper.quote_identifier(op.to)}"]
  end

  def statements(%{op: :widen_to_many} = op) do
    [
      "INSERT INTO #{qualified(op.join_table)} " <>
        ~s{("source_id", "target_id") } <>
        "SELECT #{Mapper.quote_identifier("id")}, #{Mapper.quote_identifier(op.column)} " <>
        "FROM #{qualified(op.table)} " <>
        "WHERE #{Mapper.quote_identifier(op.column)} IS NOT NULL"
    ]
  end

  defp column_definition(name, definition) do
    null_part = if definition.null, do: "", else: " NOT NULL"

    "#{Mapper.quote_identifier(name)} #{column_type(definition)}#{null_part}"
  end

  defp column_order_key("id"), do: {0, "id"}

  defp column_order_key("created_at"), do: {2, "created_at"}

  defp column_order_key("updated_at"), do: {2, "updated_at"}

  defp column_order_key(name), do: {1, name}

  defp column_type(definition) do
    collate_part =
      if definition.collation do
        " COLLATE #{Mapper.quote_identifier(definition.collation)}"
      else
        ""
      end

    "#{type_sql(definition.type)}#{collate_part}"
  end

  defp count_statement(table, predicate) do
    "SELECT COUNT(*) FROM #{qualified(table)} WHERE #{predicate}"
  end

  defp delete_action(:no_action), do: "NO ACTION"

  defp delete_action(:restrict), do: "RESTRICT"

  defp literal(value) do
    "'#{String.replace(value, "'", "''")}'"
  end

  defp qualified(name) do
    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(name)}"
  end

  defp rebuild_cast(quoted_column, []) do
    "#{quoted_column}::text"
  end

  # The searched form rather than the simple one, because a scoped entry conditions on a
  # SECOND column and CASE <expr> WHEN <value> can only compare the one. First match wins,
  # so the sort puts scoped branches before the unscoped branch for the same value - the
  # unscoped one would otherwise swallow every row the scoped one meant to single out.
  defp rebuild_cast(quoted_column, remap) do
    branches =
      remap
      |> Enum.sort_by(&{&1.from, &1.scope == nil, &1.to})
      |> Enum.map_join(" ", &remap_branch(&1, quoted_column))

    "(CASE #{branches} ELSE #{quoted_column}::text END)"
  end

  defp remap_branch(%{scope: nil} = entry, quoted_column) do
    "WHEN #{quoted_column}::text = #{literal(entry.from)} THEN #{literal(entry.to)}"
  end

  defp remap_branch(%{scope: {column, value}} = entry, quoted_column) do
    "WHEN #{quoted_column}::text = #{literal(entry.from)} " <>
      "AND #{Mapper.quote_identifier(column)} = #{literal(value)} " <>
      "THEN #{literal(entry.to)}"
  end

  defp type_sql(type) when type in @builtin_types, do: type

  defp type_sql(enum_type), do: qualified(enum_type)
end
