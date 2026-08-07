defmodule Hologram.Database.QueryRunner do
  @moduledoc false

  alias Hologram.Database.Codec
  alias Hologram.Database.Connection
  alias Hologram.Database.QueryCompiler

  @doc """
  Runs the given normalized query term against the database and returns its decoded
  result - a list of entity maps for set queries, an entity map or nil for
  single-result queries, and an integer for counting queries.

  Entity maps hold the mapping's fields under their declared names (to-one references
  under the relationship name) plus one key per included relationship - a nested
  entity map or nil for a to-one include, a list of entity maps for a to-many
  include. Param values are given in the bindings map and encoded with the slot's
  logical type.

  Raises ArgumentError when a param value is missing, or when a param value or list
  element is nil - a sometimes-nil variable branches into an explicit nil predicate
  instead.
  """
  @spec run(%{atom => any}, %{module => %{atom => any}}, %{atom => any}) ::
          list(%{atom => any}) | %{atom => any} | integer | nil
  def run(term, mapping, bindings \\ %{}) do
    compiled = QueryCompiler.compile(term, mapping)
    values = Enum.map(compiled.params, &resolve_param!(&1, bindings))

    case Connection.query(compiled.sql, values) do
      {:ok, result} -> decode_result(result, term, mapping)
      {:error, error} -> raise error
    end
  end

  defp decode_embed(nil, _sub_term, _mapping), do: nil

  defp decode_embed(values, sub_term, mapping) when is_list(values) do
    Enum.map(values, &decode_embedded_map(&1, sub_term, mapping))
  end

  defp decode_embed(object, sub_term, mapping) do
    decode_embedded_map(object, sub_term, mapping)
  end

  defp decode_embedded_map(object, sub_term, mapping) do
    target_mapping = Map.fetch!(mapping, sub_term.entity)

    base_fields =
      Map.new(target_mapping.columns, fn column ->
        value = decode_embedded_value(Map.fetch!(object, column.name), column.type)

        {field_name(column), value}
      end)

    nested_fields =
      Map.new(sub_term.include, fn {name, nested_sub_term} ->
        nested_value = Map.fetch!(object, Atom.to_string(name))

        {name, decode_embed(nested_value, nested_sub_term, mapping)}
      end)

    Map.merge(base_fields, nested_fields)
  end

  defp decode_embedded_value(nil, _type), do: nil

  defp decode_embedded_value(value, :date), do: Date.from_iso8601!(value)

  defp decode_embedded_value(value, :datetime) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)

    datetime
  end

  defp decode_embedded_value(value, :enum), do: String.to_existing_atom(value)

  defp decode_embedded_value(value, _type), do: value

  defp decode_result(%{rows: [[count]]}, %{cardinality: :count}, _mapping), do: count

  defp decode_result(%{rows: rows}, %{cardinality: :one} = term, mapping) do
    case rows do
      [] -> nil
      [row] -> decode_row(row, term, mapping)
    end
  end

  defp decode_result(%{rows: rows}, term, mapping) do
    Enum.map(rows, &decode_row(&1, term, mapping))
  end

  defp decode_row(row, term, mapping) do
    entity_mapping = Map.fetch!(mapping, term.entity)
    {column_values, include_values} = Enum.split(row, length(entity_mapping.columns))

    base_fields =
      entity_mapping.columns
      |> Enum.zip(column_values)
      |> Map.new(fn {column, value} ->
        {field_name(column), Codec.decode(value, column.type)}
      end)

    include_fields =
      term.include
      |> Enum.sort_by(fn {name, _sub_term} -> name end)
      |> Enum.zip(include_values)
      |> Map.new(fn {{name, sub_term}, value} ->
        {name, decode_embed(value, sub_term, mapping)}
      end)

    Map.merge(base_fields, include_fields)
  end

  defp encode_param!(values, name, {:list, type}) when is_list(values) do
    Enum.map(values, fn
      nil ->
        raise ArgumentError,
          message:
            "nil element in the list for param #{inspect(name)} - use an explicit nil predicate instead"

      value ->
        Codec.encode(value, type)
    end)
  end

  defp encode_param!(value, _name, type), do: Codec.encode(value, type)

  defp field_name(%{source: :system, name: name}), do: String.to_existing_atom(name)

  defp field_name(%{source: {:attribute, name}}), do: name

  defp field_name(%{source: {:relationship, name}}), do: name

  defp resolve_param!({:value, encoded_value}, _bindings), do: encoded_value

  defp resolve_param!({:param, name, type}, bindings) do
    case Map.fetch(bindings, name) do
      :error ->
        raise ArgumentError, message: "missing value for param #{inspect(name)}"

      {:ok, nil} ->
        raise ArgumentError,
          message: "nil value for param #{inspect(name)} - use an explicit nil predicate instead"

      {:ok, value} ->
        encode_param!(value, name, type)
    end
  end
end
