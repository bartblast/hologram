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

  :add_foreign_key renders a named ADD CONSTRAINT referencing the target table's id
  column with the delete action - :drop_foreign_key and :rename_constraint render
  their ALTER TABLE forms. :create_index renders a named index over its columns -
  :drop_index renders the schema-qualified drop (indexes are schema-level objects).

  :create_enum_type, :drop_enum_type, :add_enum_value (with its BEFORE anchor when
  positioned), and :rename_enum_value render one statement each. :rebuild_enum_type
  renders the rebuild sequence: rename the old type aside, create the replacement
  under the canonical name, cast every column using the type (through text, applying
  the optional old-to-new value remap as a CASE expression), then drop the old type.
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
        {:before, anchor} -> " BEFORE #{enum_literal(anchor)}"
        nil -> ""
      end

    [
      "ALTER TYPE #{qualified(op.enum_type)} " <>
        "ADD VALUE #{enum_literal(op.value)}#{position_part}"
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
    values = Enum.map_join(op.values, ", ", &enum_literal/1)

    ["CREATE TYPE #{qualified(op.enum_type)} AS ENUM (#{values})"]
  end

  def statements(%{op: :create_index} = op) do
    columns = Enum.map_join(op.columns, ", ", &Mapper.quote_identifier/1)

    [
      "CREATE INDEX #{Mapper.quote_identifier(op.index)} " <>
        "ON #{qualified(op.table)} (#{columns})"
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
    remap = Map.get(op, :remap, %{})

    rename_statement =
      "ALTER TYPE #{qualified(op.enum_type)} RENAME TO #{Mapper.quote_identifier(old_type)}"

    create_statement =
      "CREATE TYPE #{qualified(op.enum_type)} AS ENUM " <>
        "(#{Enum.map_join(op.values, ", ", &enum_literal/1)})"

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

  def statements(%{op: :rename_enum_value} = op) do
    [
      "ALTER TYPE #{qualified(op.enum_type)} " <>
        "RENAME VALUE #{enum_literal(op.from)} TO #{enum_literal(op.to)}"
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

  defp delete_action(:restrict), do: "RESTRICT"

  defp enum_literal(value) do
    "'#{String.replace(value, "'", "''")}'"
  end

  defp qualified(name) do
    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(name)}"
  end

  defp rebuild_cast(quoted_column, remap) when remap == %{} do
    "#{quoted_column}::text"
  end

  defp rebuild_cast(quoted_column, remap) do
    branches =
      remap
      |> Enum.sort()
      |> Enum.map_join(" ", fn {old_value, new_value} ->
        "WHEN #{enum_literal(old_value)} THEN #{enum_literal(new_value)}"
      end)

    "(CASE #{quoted_column}::text #{branches} ELSE #{quoted_column}::text END)"
  end

  defp type_sql(type) when type in @builtin_types, do: type

  defp type_sql(enum_type), do: qualified(enum_type)
end
