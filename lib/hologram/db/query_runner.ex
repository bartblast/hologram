defmodule Hologram.DB.QueryRunner do
  @moduledoc false

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.QueryCompiler
  alias Hologram.DB.SortKey
  alias Hologram.Entity.Metadata
  alias Hologram.Entity.Validator
  alias Hologram.Policy
  alias Hologram.Query

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

  Bindings are validated before execution: a binding for a placeholder the query does not
  define raises, and each given value must match the logical type of the attribute
  its placeholder meets, enum membership included. A membership placeholder takes a list whose
  elements are validated the same way - an empty list is legal and matches nothing.

  Raises ArgumentError when a binding is invalid, when a placeholder value is missing, or
  when a placeholder value or list element is nil - a sometimes-nil variable branches into
  an explicit nil predicate instead.
  """
  @spec run(Query.t(), %{module => %{atom => any}}, %{atom => any}) ::
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

  @doc false
  @spec run_policied(Query.t(), %{module => %{atom => any}}, String.t() | nil, %{atom => any}) ::
          list(struct) | struct | integer | nil
  def run_policied(term, mapping, actor_user_id, bindings \\ %{}) do
    validate_bindings!(term, bindings)

    policy = %{
      anonymous?: is_nil(actor_user_id),
      operation: :read,
      rules: read_rules(term.entity)
    }

    compiled = QueryCompiler.compile(term, mapping, policy)
    values = Enum.map(compiled.params, &resolve_param!(&1, bindings, actor_user_id))

    case Connection.query(compiled.sql, values) do
      {:ok, result} -> decode_result(result, term, mapping)
      {:error, error} -> raise error
    end
  end

  # A name matching no attribute definition is a to-one reference field - every reference
  # column carries the entity id type, and a bound value is never nil (nil placeholders raise).
  defp attribute_definition(entity_type, attribute_name) do
    definitions = entity_type.__attributes__() ++ entity_type.__system_attributes__()

    case Enum.find(definitions, fn {name, _type, _opts} -> name == attribute_name end) do
      {_name, type, opts} -> {type, opts}
      nil -> {:uuid, []}
    end
  end

  # Conflicts mirror the registry's placeholder-shape rule: one placeholder name binds one
  # logical type - identical rebinding is reuse, a differing kind or type raises.
  defp binding_description(:list, type), do: inspect({:list, type})

  defp binding_description(:scalar, type), do: inspect(type)

  # Conflicts mirror the registry's placeholder-shape rule: one placeholder name binds one
  # logical type - identical rebinding is reuse, a differing kind or type raises.
  defp collect_definition(acc, placeholder_name, {kind, type, _opts} = definition) do
    case Map.fetch(acc, placeholder_name) do
      {:ok, {^kind, ^type, _existing_opts}} ->
        acc

      {:ok, {existing_kind, existing_type, _existing_opts}} ->
        raise ArgumentError,
          message:
            "placeholder #{inspect(placeholder_name)} binds as #{binding_description(existing_kind, existing_type)} and #{binding_description(kind, type)} - rename one of the conflicting variables"

      :error ->
        Map.put(acc, placeholder_name, definition)
    end
  end

  # A placeholder as a membership list element binds a single value of the attribute's
  # type.
  defp collect_param_definitions(term, acc) do
    acc_with_filters =
      Enum.reduce(term.filter, acc, fn
        {attribute_name, operator, {:placeholder, placeholder_name}}, inner_acc ->
          {type, opts} = attribute_definition(term.entity, attribute_name)
          kind = if operator in [:in, :not_in], do: :list, else: :scalar

          collect_definition(inner_acc, placeholder_name, {kind, type, opts})

        {attribute_name, _operator, values}, inner_acc when is_list(values) ->
          {type, opts} = attribute_definition(term.entity, attribute_name)

          values
          |> Enum.filter(&match?({:placeholder, _placeholder_name}, &1))
          |> Enum.reduce(inner_acc, fn {:placeholder, placeholder_name}, deeper_acc ->
            collect_definition(deeper_acc, placeholder_name, {:scalar, type, opts})
          end)

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
      |> Enum.reject(&(&1.source == :revisions or match?({:sort_key, _name}, &1.source)))
      |> Map.new(fn column ->
        value = decode_embedded_value(Map.fetch!(object, column.name), column.type)

        {field_name(column), value}
      end)

    nested_fields =
      Map.new(sub_term.include, fn {name, nested_sub_term} ->
        nested_value = Map.fetch!(object, Atom.to_string(name))

        {name, decode_embed(nested_value, nested_sub_term, mapping)}
      end)

    revisions_column = Enum.find(target_mapping.columns, &(&1.source == :revisions))

    revisions =
      object
      |> Map.fetch!(revisions_column.name)
      |> decode_embedded_value(revisions_column.type)
      |> revisions_from_row(target_mapping.columns)

    struct!(
      sub_term.entity,
      base_fields
      |> Map.merge(nested_fields)
      |> Map.put(:__meta__, %Metadata{revisions: revisions})
    )
  end

  defp decode_embedded_value(nil, _type), do: nil

  defp decode_embedded_value(value, :date), do: Date.from_iso8601!(value)

  # JSON writes a fraction without its trailing zeros, so an instant arriving this way carries
  # whatever precision its digits imply, where the same instant read from the column carries all
  # six. Two structs of one instant that compare unequal is a difference an application meets as
  # a bug - the same row read two ways answering differently - so what arrives here is
  # normalized the way the column path already normalizes it.
  defp decode_embedded_value(value, :datetime) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)

    Codec.encode(datetime, :datetime)
  end

  defp decode_embedded_value(value, :enum), do: Codec.decode_enum_label(value)

  # Same story as :datetime one type over - JSON drops a fraction's trailing zeros, so a time
  # arriving this way is spelled shorter than the same time read from its own column, which is
  # always six digits. Promoted here so that one time of day is one struct however it was read.
  defp decode_embedded_value(value, :time) do
    value
    |> Time.from_iso8601!()
    |> Codec.encode(:time)
  end

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

    column_pairs = Enum.zip(entity_mapping.columns, column_values)

    # Exactly one revisions column per table, by construction - it is framework state rather than
    # a value the entity declares, so it lands in the metadata and never as a field.
    {[{revisions_column, revisions_value}], value_pairs} =
      Enum.split_with(column_pairs, fn {column, _value} -> column.source == :revisions end)

    base_fields =
      value_pairs
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

    revisions =
      revisions_value
      |> Codec.decode(revisions_column.type)
      |> revisions_from_row(entity_mapping.columns)

    struct!(
      term.entity,
      base_fields
      |> Map.merge(include_fields)
      |> Map.put(:__meta__, %Metadata{revisions: revisions})
    )
  end

  defp encode_param!(values, name, {:list, type}) when is_list(values) do
    Enum.map(values, fn
      nil ->
        raise ArgumentError,
          message:
            "nil element in the list for placeholder #{inspect(name)} - use an explicit nil predicate instead"

      value ->
        Codec.encode(value, type)
    end)
  end

  # The key slot of a string comparison carries the bound's key, computed here from the same
  # value the raw slot carries - so the pair the statement compares is folded the way the
  # column's own pair is.
  defp encode_param!(value, _name, :sort_key), do: SortKey.compute(value)

  defp encode_param!(value, _name, type), do: Codec.encode(value, type)

  defp expected_description(:enum, opts) do
    "one of #{inspect(Keyword.fetch!(opts, :values))}"
  end

  defp expected_description(type, _opts), do: "a #{inspect(type)} value"

  defp field_name(%{source: :system, name: name}), do: String.to_existing_atom(name)

  defp field_name(%{source: {:attribute, name}}), do: name

  defp field_name(%{source: {:relationship, name}}), do: String.to_existing_atom("#{name}_id")

  defp read_rules(entity_type) do
    entity_type
    |> Policy.build()
    |> Map.get(:read, [])
  end

  # The actor slot never appears in an anonymous statement - actor-referencing rules are
  # elided at composition, so there is no nil to bind.
  defp resolve_param!(:actor, _bindings, actor_user_id), do: Codec.encode(actor_user_id, :uuid)

  defp resolve_param!(slot, bindings, _actor_user_id), do: resolve_param!(slot, bindings)

  defp resolve_param!({:value, encoded_value}, _bindings), do: encoded_value

  defp resolve_param!({:placeholder, name, type}, bindings) do
    case Map.fetch(bindings, name) do
      :error ->
        raise ArgumentError, message: "missing value for placeholder #{inspect(name)}"

      {:ok, nil} ->
        raise ArgumentError,
          message:
            "nil value for placeholder #{inspect(name)} - use an explicit nil predicate instead"

      {:ok, value} ->
        encode_param!(value, name, type)
    end
  end

  # The same reading EntityOperations.revisions_from_row/2 does for a by-id read, beside the
  # field_name/1 clauses this module already keeps its own copy of.
  defp revisions_from_row(revisions, columns) do
    revisions
    |> Enum.flat_map(fn {name, revision} ->
      case Enum.find(columns, &(&1.name == name)) do
        nil -> []
        column -> [{field_name(column), revision}]
      end
    end)
    |> Map.new()
  end

  defp validate_binding!(name, values, :list, type, opts) when is_list(values) do
    Enum.each(values, fn
      nil ->
        :ok

      value ->
        if not Validator.attribute_value_valid?(value, type, opts) do
          raise ArgumentError,
            message:
              "invalid element #{inspect(value)} in the list for placeholder #{inspect(name)} - expected #{expected_description(type, opts)}"
        end
    end)
  end

  defp validate_binding!(name, value, :list, _type, _opts) do
    raise ArgumentError,
      message:
        "non-list value #{inspect(value)} for placeholder #{inspect(name)} - the placeholder binds a membership list"
  end

  defp validate_binding!(name, value, :scalar, type, opts) do
    if not Validator.attribute_value_valid?(value, type, opts) do
      raise ArgumentError,
        message:
          "invalid value #{inspect(value)} for placeholder #{inspect(name)} - expected #{expected_description(type, opts)}"
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
          "the query defines no placeholders"
        else
          "the query defines placeholders #{inspect(defined_names)}"
        end

      raise ArgumentError,
        message: "unknown placeholder #{inspect(hd(unknown_names))} in bindings - #{description}"
    end

    :ok
  end
end
