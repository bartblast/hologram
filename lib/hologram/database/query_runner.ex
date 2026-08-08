defmodule Hologram.Database.QueryRunner do
  @moduledoc false

  alias Hologram.Database.Codec
  alias Hologram.Database.Connection
  alias Hologram.Database.QueryCompiler
  alias Hologram.Entity.Validator

  @doc """
  Runs the given normalized query term against the database and returns its decoded
  result - a list of entity structs for set queries, an entity struct or nil for
  single-result queries, and an integer for counting queries.

  Entity structs hold the mapping's fields under their declared names (to-one
  references under their `<name>_id` fields). Each included relationship fills its
  embed field - a nested entity struct or nil for a to-one include, a list of entity
  structs for a to-many include - and relationships the query did not include keep
  their NotIncluded defaults. Param values are given in the bindings map and encoded
  with the slot's logical type.

  Bindings are validated before execution: a binding for a param the query does not
  define raises, and each given value must match the logical type of the attribute
  its param meets, enum membership included. A membership param takes a list whose
  elements are validated the same way - an empty list is legal and matches nothing.

  Raises ArgumentError when a binding is invalid, when a param value is missing, or
  when a param value or list element is nil - a sometimes-nil variable branches into
  an explicit nil predicate instead.
  """
  @spec run(%{atom => any}, %{module => %{atom => any}}, %{atom => any}) ::
          list(struct) | struct | integer | nil
  def run(term, mapping, bindings \\ %{}) do
    validate_bindings!(term, bindings)

    compiled = QueryCompiler.compile(term, mapping)
    values = Enum.map(compiled.params, &resolve_param!(&1, bindings))

    case Connection.query(compiled.sql, values) do
      {:ok, result} -> decode_result(result, term, mapping)
      {:error, error} -> raise error
    end
  end

  defp attribute_definition(entity_type, attribute_name) do
    definitions = entity_type.__attributes__() ++ entity_type.__system_attributes__()

    {_name, type, opts} =
      Enum.find(definitions, fn {name, _type, _opts} -> name == attribute_name end)

    {type, opts}
  end

  defp collect_param_definitions(term, acc) do
    acc_with_filters =
      Enum.reduce(term.filter, acc, fn
        {attribute_name, operator, {:param, param_name}}, inner_acc ->
          {type, opts} = attribute_definition(term.entity, attribute_name)
          kind = if operator in [:in, :not_in], do: :list, else: :scalar

          Map.put_new(inner_acc, param_name, {kind, type, opts})

        _triple, inner_acc ->
          inner_acc
      end)

    term.include
    |> Map.values()
    |> Enum.reduce(acc_with_filters, fn sub_term, inner_acc ->
      collect_param_definitions(sub_term, inner_acc)
    end)
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
      target_mapping.columns
      |> Enum.reject(&match?({:sort_key, _name}, &1.source))
      |> Map.new(fn column ->
        value = decode_embedded_value(Map.fetch!(object, column.name), column.type)

        {field_name(column), value}
      end)

    nested_fields =
      Map.new(sub_term.include, fn {name, nested_sub_term} ->
        nested_value = Map.fetch!(object, Atom.to_string(name))

        {name, decode_embed(nested_value, nested_sub_term, mapping)}
      end)

    struct!(sub_term.entity, Map.merge(base_fields, nested_fields))
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
      |> Enum.reject(fn {column, _value} -> match?({:sort_key, _name}, column.source) end)
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

    struct!(term.entity, Map.merge(base_fields, include_fields))
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

  defp expected_description(:enum, opts) do
    "one of #{inspect(Keyword.fetch!(opts, :values))}"
  end

  defp expected_description(type, _opts), do: "a #{inspect(type)} value"

  defp field_name(%{source: :system, name: name}), do: String.to_existing_atom(name)

  defp field_name(%{source: {:attribute, name}}), do: name

  defp field_name(%{source: {:relationship, name}}), do: String.to_existing_atom("#{name}_id")

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

  defp validate_binding!(name, values, :list, type, opts) when is_list(values) do
    Enum.each(values, fn
      nil ->
        :ok

      value ->
        if not Validator.attribute_value_valid?(value, type, opts) do
          raise ArgumentError,
            message:
              "invalid element #{inspect(value)} in the list for param #{inspect(name)} - expected #{expected_description(type, opts)}"
        end
    end)
  end

  defp validate_binding!(name, value, :list, _type, _opts) do
    raise ArgumentError,
      message:
        "non-list value #{inspect(value)} for param #{inspect(name)} - the param binds a membership list"
  end

  defp validate_binding!(name, value, :scalar, type, opts) do
    if not Validator.attribute_value_valid?(value, type, opts) do
      raise ArgumentError,
        message:
          "invalid value #{inspect(value)} for param #{inspect(name)} - expected #{expected_description(type, opts)}"
    end

    :ok
  end

  # Nil values are skipped here on purpose - resolve_param! and encode_param!
  # raise their dedicated messages for them.
  defp validate_bindings!(term, bindings) do
    param_definitions = collect_param_definitions(term, %{})

    validate_known_params!(bindings, param_definitions)

    Enum.each(param_definitions, fn {name, {kind, type, opts}} ->
      case Map.fetch(bindings, name) do
        {:ok, nil} -> :ok
        {:ok, value} -> validate_binding!(name, value, kind, type, opts)
        :error -> :ok
      end
    end)
  end

  defp validate_known_params!(bindings, param_definitions) do
    unknown_names =
      bindings
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(param_definitions, &1))
      |> Enum.sort()

    if unknown_names != [] do
      defined_names =
        param_definitions
        |> Map.keys()
        |> Enum.sort()

      description =
        if defined_names == [] do
          "the query defines no params"
        else
          "the query defines params #{inspect(defined_names)}"
        end

      raise ArgumentError,
        message: "unknown param #{inspect(hd(unknown_names))} in bindings - #{description}"
    end

    :ok
  end
end
