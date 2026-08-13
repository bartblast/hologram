defmodule Hologram.DB.Preflight do
  @moduledoc false

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.DDL

  @doc """
  Returns the encoded fill value for the given table's column, or :none when the column
  declares no default.

  A required column arriving on a populated table takes its declared default: the value
  fills the existing rows before the column tightens, so the DDL never carries values.
  """
  @spec fill_value(%{module => %{atom => any}}, String.t(), String.t()) ::
          {:ok, any} | :none
  def fill_value(mapping, table, column_name) do
    entity_mapping =
      mapping
      |> Map.values()
      |> Enum.find(&(&1.table == table))

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
  """
  @spec run!(list(%{atom => any}), %{atom => any}, %{module => %{atom => any}}) :: :ok
  def run!(ops, actual, mapping) do
    Enum.each(ops, &check_op!(&1, actual, mapping))
  end

  defp check_op!(%{op: :add_column} = op, _actual, mapping) do
    # An op carrying its own backfill needs no declared default - a migration states what
    # the rows that predate the column receive.
    filled? =
      Map.has_key?(op, :backfill) or
        match?({:ok, _value}, fill_value(mapping, op.table, op.column))

    checked? = not op.definition.null and not filled?

    count = if checked?, do: count_result(DDL.rows_check_statement(op.table)), else: 0

    if count > 0 do
      raise ~s(cannot add required column "#{op.column}" to table "#{op.table}" - ) <>
              "#{count} existing #{pluralize_rows(count)} would have no value - " <>
              "declare a default:, make the attribute optional:, or clear the rows"
    end
  end

  defp check_op!(%{op: :alter_column} = op, _actual, mapping) do
    check_type_change!(op)
    check_null_tightening!(op, mapping)
  end

  # Only a table that already stands can hold duplicates - one this run creates is born
  # empty, and its rows would not be there to query anyway.
  defp check_op!(%{op: :create_index, unique: true} = op, actual, _mapping) do
    count =
      if Map.has_key?(actual.tables, op.table) do
        count_result(DDL.duplicate_check_statement(op.table, op.columns, op.nulls_distinct))
      else
        0
      end

    if count > 0 do
      columns = Enum.map_join(op.columns, ", ", &~s("#{&1}"))

      raise ~s{found #{count} duplicate #{pluralize_keys(count)} in "#{op.table}" } <>
              "over (#{columns}) - a unique index cannot be built while rows repeat a " <>
              "key - update the rows or drop the unique declaration"
    end
  end

  defp check_op!(%{op: :rebuild_enum_type} = op, actual, _mapping) do
    removed_values = actual.enum_types[op.enum_type] -- op.values

    if removed_values != [] do
      Enum.each(op.columns, fn {table, column} ->
        check_removed_enum_values!(table, column, removed_values)
      end)
    end
  end

  defp check_op!(_op, _actual, _mapping), do: :ok

  defp check_cast_rows!(op) do
    count =
      count_result(DDL.cast_check_statement(op.table, op.column, op.before.type, op.after.type))

    if count > 0 do
      raise ~s(#{count} #{pluralize_rows(count)} in "#{op.table}"."#{op.column}" ) <>
              "cannot convert from #{op.before.type} to #{op.after.type} - " <>
              "fix the data or remove the attribute and re-add it with the new type"
    end
  end

  defp check_null_tightening!(op, mapping) do
    fillable? =
      op.before.type == op.after.type and
        match?({:ok, _value}, fill_value(mapping, op.table, op.column))

    checked? = op.before.null and not op.after.null and not fillable?
    count = if checked?, do: count_result(DDL.null_check_statement(op.table, op.column)), else: 0

    if count > 0 do
      raise ~s(cannot make column "#{op.column}" on table "#{op.table}" required - ) <>
              "found #{count} #{pluralize_rows(count)} with NULL - " <>
              "declare a default:, keep the attribute optional:, or fix the data"
    end
  end

  defp check_removed_enum_values!(table, column, removed_values) do
    count = count_result(DDL.enum_values_check_statement(table, column, removed_values))

    if count > 0 do
      values = Enum.map_join(removed_values, ", ", &"'#{&1}'")

      raise ~s(found #{count} #{pluralize_rows(count)} in "#{table}"."#{column}" ) <>
              "holding removed enum #{pluralize_values(removed_values)} #{values} - " <>
              "update the rows or re-add the #{pluralize_values(removed_values)}"
    end
  end

  defp check_type_change!(op) do
    if op.before.type != op.after.type do
      case DDL.cast_class(op.before.type, op.after.type) do
        :safe ->
          :ok

        :data_dependent ->
          check_cast_rows!(op)

        :unsupported ->
          raise ~s(changing column "#{op.column}" on table "#{op.table}" ) <>
                  "from #{op.before.type} to #{op.after.type} is not supported - " <>
                  "remove the attribute and re-add it with the new type"
      end
    end
  end

  defp count_result(statement) do
    {:ok, %{rows: [[count]]}} = Connection.query(statement)

    count
  end

  defp pluralize_keys(1), do: "key"

  defp pluralize_keys(_count), do: "keys"

  defp pluralize_rows(1), do: "row"

  defp pluralize_rows(_count), do: "rows"

  defp pluralize_values([_value]), do: "value"

  defp pluralize_values(_values), do: "values"
end
