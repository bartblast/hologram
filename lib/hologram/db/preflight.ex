defmodule Hologram.DB.Preflight do
  @moduledoc false

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.DDL

  @doc """
  Validates that filling the NULLs of the given table's column with the given encoded value
  makes no rows repeat a key of a unique index the mapping gives the table.

  Returns :ok, or raises naming the column, the key and how many keys would repeat. A column
  made required takes its default in the rows that hold NULL, and NULL never repeats a key
  while the default can - under an index that already stands the fill itself would fail, so
  this asks before it. Only the keys the fill would make repeat are counted: rows that repeat
  a key without it are the index build's to refuse.
  """
  @spec check_fill!(%{module => %{atom => any}}, String.t(), String.t(), any) :: :ok
  def check_fill!(mapping, table, column_name, encoded_value) do
    mapping
    |> unique_indexes_over(table, column_name)
    |> Enum.each(fn index ->
      statement =
        DDL.filled_duplicate_check_statement(
          table,
          index.columns,
          column_name,
          index.nulls_distinct
        )

      {:ok, %{rows: [[count]]}} = Connection.query(statement, [encoded_value])

      raise_filled_duplicate_keys!(table, column_name, index.columns, count)
    end)
  end

  @doc """
  Validates that the rows the given unique index op's table holds at this moment repeat no key
  of the index.

  Returns :ok, or raises naming the table, its columns and how many keys repeat. The check run!/3
  makes before any DDL sees the rows as they stood then, so a run that adds a column filled
  with its default asks again here, with every column of the index in place.
  """
  @spec check_unique_index!(%{atom => any}) :: :ok
  def check_unique_index!(op) do
    statement = DDL.duplicate_check_statement(op.table, op.columns, op.nulls_distinct)

    raise_duplicate_keys!(op, count_result(statement))
  end

  @doc """
  Returns the encoded fill value for the given table's column, or :none when the column
  declares no default.

  A required column arriving on a populated table takes its declared default: the value
  fills the existing rows before the column tightens, so the DDL never carries values.
  """
  @spec fill_value(%{module => %{atom => any}}, String.t(), String.t()) ::
          {:ok, any} | :none
  def fill_value(mapping, table, column_name) do
    entity_mapping = entity_mapping(mapping, table)

    column = entity_mapping && Enum.find(entity_mapping.columns, &(&1.name == column_name))

    case column do
      %{default: nil} -> :none
      %{default: default, type: type} -> {:ok, Codec.encode(default, type)}
      nil -> :none
    end
  end

  @doc """
  Validates that the existing rows can follow the given change ops, against the given
  introspected schema and mapping.

  Returns :ok, or raises naming the obstacle and the ways out - the transformations rows
  cannot follow fail before any DDL runs, so PostgreSQL never arbitrates: an error
  surfacing from an apply is by definition a Hologram bug.

  A check against a table the ops create, or a unique index over a column they add, answers
  zero without a query: the table holds no rows yet, and the column is not there to ask
  about. A run that fills columns asks about its unique indexes again: before it fills the
  NULLs of a column that stands (see check_fill!/4), and right before it builds an index (see
  check_unique_index!/1).

  An enum rebuild's removed values exclude the ones an unscoped remap carries: those rows
  follow the value to its new label rather than losing it.
  """
  @spec run!(list(%{atom => any}), %{atom => any}, %{module => %{atom => any}}) :: :ok
  def run!(ops, actual, mapping) do
    Enum.each(ops, &check_op!(&1, actual, mapping))
  end

  defp check_op!(%{op: :add_column} = op, actual, mapping) do
    # An op carrying its own backfill needs no declared default - a migration states what
    # the rows that predate the column receive.
    filled? =
      Map.has_key?(op, :backfill) or
        match?({:ok, _value}, fill_value(mapping, op.table, op.column))

    checked? = not op.definition.null and not filled?

    count =
      if checked?,
        do: count_existing(actual, op.table, DDL.rows_check_statement(op.table)),
        else: 0

    if count > 0 do
      raise ~s(cannot add required column "#{op.column}" to table "#{op.table}" - ) <>
              "#{count} existing #{pluralize_rows(count)} would have no value - " <>
              "declare default: <value>, make the attribute optional: true, or clear the rows"
    end
  end

  defp check_op!(%{op: :alter_column} = op, actual, mapping) do
    check_type_change!(op, actual)
    check_null_tightening!(op, actual, mapping)
  end

  # An index over a column the run adds is not asked about here: the column is not there to
  # query. A unique attribute declares no default, so its column arrives NULL in every row, and
  # NULL is never a duplicate key on a declared unique index, which keeps nulls distinct - the
  # one index comparing nulls as values, the role grant store's, is born with its table. A key
  # declared with unique may name a column that arrives filled with its default, though - so
  # a run asks again right before it builds the index, with the added columns filled (see
  # check_unique_index!/1). A run filling the NULLs of a column that stands asks before that
  # fill (see check_fill!/4).
  defp check_op!(%{op: :create_index, unique: true} = op, actual, _mapping) do
    statement = DDL.duplicate_check_statement(op.table, op.columns, op.nulls_distinct)

    raise_duplicate_keys!(op, count_existing(actual, op.table, op.columns, statement))
  end

  # An enum type this run creates has no values to lose - it reaches the database with
  # exactly the ones being rebuilt. One file can hold both: a rendering chunk creates the
  # type, and a later chunk of the same file reorders or drops values in it, while the
  # schema this checks against is the one from before the file ran.
  defp check_op!(%{op: :rebuild_enum_type} = op, actual, _mapping) do
    existing_values = Map.get(actual.enum_types, op.enum_type, [])
    removed_values = (existing_values -- op.values) -- carried_values(op)

    if removed_values != [] do
      Enum.each(op.columns, fn {table, column} ->
        check_removed_enum_values!(actual, table, column, removed_values)
      end)
    end
  end

  defp check_op!(_op, _actual, _mapping), do: :ok

  defp check_cast_rows!(op, actual) do
    statement = DDL.cast_check_statement(op.table, op.column, op.before.type, op.after.type)
    count = count_existing(actual, op.table, statement)

    if count > 0 do
      raise ~s(#{count} #{pluralize_rows(count)} in "#{op.table}"."#{op.column}" ) <>
              "cannot convert from #{op.before.type} to #{op.after.type} - " <>
              "fix the data or remove the attribute and re-add it with the new type"
    end
  end

  # A value the rebuild carries to a new label is not a value it removes: the rows holding it
  # follow it through the remap, so counting them would refuse the very rename doing the
  # carrying. Only an UNSCOPED entry says that of every row - a scoped one carries the rows of
  # one entity type and leaves the rest, which is a removal for those.
  defp carried_values(op) do
    op
    |> Map.get(:remap, [])
    |> Enum.filter(&(&1.scope == nil))
    |> Enum.map(& &1.from)
  end

  defp check_null_tightening!(op, actual, mapping) do
    fillable? =
      op.before.type == op.after.type and
        match?({:ok, _value}, fill_value(mapping, op.table, op.column))

    checked? = op.before.null and not op.after.null and not fillable?
    statement = DDL.null_check_statement(op.table, op.column)
    count = if checked?, do: count_existing(actual, op.table, statement), else: 0

    if count > 0 do
      raise ~s(cannot make column "#{op.column}" on table "#{op.table}" required - ) <>
              "found #{count} #{pluralize_rows(count)} with NULL - " <>
              "declare default: <value>, keep the attribute optional: true, or fix the data"
    end
  end

  defp check_removed_enum_values!(actual, table, column, removed_values) do
    statement = DDL.enum_values_check_statement(table, column, removed_values)
    count = count_existing(actual, table, statement)

    if count > 0 do
      values = Enum.map_join(removed_values, ", ", &"'#{&1}'")

      raise ~s(found #{count} #{pluralize_rows(count)} in "#{table}"."#{column}" ) <>
              "holding removed enum #{pluralize_values(removed_values)} #{values} - " <>
              "update the rows or re-add the #{pluralize_values(removed_values)}"
    end
  end

  defp check_type_change!(op, actual) do
    if op.before.type != op.after.type do
      case DDL.cast_class(op.before.type, op.after.type) do
        :safe ->
          :ok

        :data_dependent ->
          check_cast_rows!(op, actual)

        :unsupported ->
          raise ~s(changing column "#{op.column}" on table "#{op.table}" ) <>
                  "from #{op.before.type} to #{op.after.type} is not supported - " <>
                  "remove the attribute and re-add it with the new type"
      end
    end
  end

  # Every check here counts the rows that cannot follow a change, and a table this file
  # creates has none to count - it does not exist in the schema this runs against, so the
  # query would raise undefined_table instead of answering zero. The renderer can put the
  # create and a later change to the same table in different chunks, which is how an op
  # naming a table absent from the introspected schema reaches this at all.
  defp count_existing(actual, table, statement) do
    if Map.has_key?(actual.tables, table), do: count_result(statement), else: 0
  end

  # The same for a column the run adds to a table that stands: the query would raise
  # undefined_column, and the column has no rows' values to count yet.
  defp count_existing(actual, table, columns, statement) do
    case Map.fetch(actual.tables, table) do
      {:ok, %{columns: existing_columns}} ->
        if Enum.all?(columns, &Map.has_key?(existing_columns, &1)),
          do: count_result(statement),
          else: 0

      :error ->
        0
    end
  end

  defp count_result(statement) do
    {:ok, %{rows: [[count]]}} = Connection.query(statement)

    count
  end

  defp entity_mapping(mapping, table) do
    mapping
    |> Map.values()
    |> Enum.find(&(&1.table == table))
  end

  defp raise_duplicate_keys!(_op, 0), do: :ok

  defp raise_duplicate_keys!(op, count) do
    columns = Enum.map_join(op.columns, ", ", &~s("#{&1}"))

    raise ~s{found #{count} duplicate #{pluralize_keys(count)} in "#{op.table}" } <>
            "over (#{columns}) - a unique index cannot be built while rows repeat a " <>
            "key - update the rows or drop the unique declaration"
  end

  defp raise_filled_duplicate_keys!(_table, _column, _columns, 0), do: :ok

  defp raise_filled_duplicate_keys!(table, column, columns, count) do
    key = Enum.map_join(columns, ", ", &~s("#{&1}"))

    raise ~s(cannot make column "#{column}" on table "#{table}" required - ) <>
            "filling its NULLs with the default would make #{count} " <>
            "#{pluralize_keys(count)} repeat over (#{key}) - " <>
            "fix the data, keep the attribute optional: true, or drop the unique declaration"
  end

  defp pluralize_keys(1), do: "key"

  defp pluralize_keys(_count), do: "keys"

  defp pluralize_rows(1), do: "row"

  defp pluralize_rows(_count), do: "rows"

  defp pluralize_values([_value]), do: "value"

  defp pluralize_values(_values), do: "values"

  # The column indexes a mapping derives are never unique, so the entity's own index entries
  # hold every unique index of its table.
  defp unique_indexes_over(mapping, table, column_name) do
    case entity_mapping(mapping, table) do
      nil ->
        []

      %{indexes: indexes} ->
        indexes
        |> Enum.sort_by(fn {name, _index} -> name end)
        |> Enum.map(fn {_name, index} -> index end)
        |> Enum.filter(&(&1.unique and column_name in &1.columns))
    end
  end
end
