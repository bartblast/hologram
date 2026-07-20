defmodule Hologram.Database.DDL do
  @moduledoc false

  alias Hologram.Database.Mapper

  # Types the mapper emits by name - anything else is a derived enum type, which lives
  # in the data schema and must be schema-qualified and quoted.
  @builtin_types ["boolean", "date", "float8", "int8", "text", "timestamptz", "uuid"]

  @data_schema "hologram_data"

  @doc """
  Returns the DDL statements that execute the given change op, in execution order.

  :create_table renders one statement with all columns and the named primary key
  constraint - columns are laid out in canonical order (id first, created_at and
  updated_at last, everything else alphabetical). :add_column, :drop_column, and
  :drop_table render one statement each. :alter_column renders one ALTER TABLE
  statement combining a type action (with COLLATE and a USING cast) and a nullability
  action, as needed.
  """
  @spec statements(%{atom => any}) :: list(String.t())
  def statements(%{op: :add_column} = op) do
    [
      "ALTER TABLE #{qualified(op.table)} " <>
        "ADD COLUMN #{column_definition(op.column, op.definition)}"
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

    lines = Enum.join(column_lines ++ [pk_line], ",\n")

    ["CREATE TABLE #{qualified(op.table)} (\n#{lines}\n)"]
  end

  def statements(%{op: :drop_column} = op) do
    ["ALTER TABLE #{qualified(op.table)} DROP COLUMN #{Mapper.quote_identifier(op.column)}"]
  end

  def statements(%{op: :drop_table} = op) do
    ["DROP TABLE #{qualified(op.table)}"]
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

  defp qualified(name) do
    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(name)}"
  end

  defp type_sql(type) when type in @builtin_types, do: type

  defp type_sql(enum_type), do: qualified(enum_type)
end
