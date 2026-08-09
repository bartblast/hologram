defmodule Hologram.Entity.Validator do
  @moduledoc false

  alias Hologram.Commons.Types, as: T
  alias Hologram.Reflection

  @bounded_attribute_types [:date, :datetime, :float, :integer]

  # Postgres int8 column bounds
  @max_integer 9_223_372_036_854_775_807
  @min_integer -9_223_372_036_854_775_808

  @reserved_names [:created_at, :id, :updated_at]

  @valid_attribute_opts [
    :default,
    :format,
    :in,
    :length,
    :max,
    :max_length,
    :min,
    :min_length,
    :optional,
    :values
  ]

  @valid_attribute_types [:boolean, :date, :datetime, :enum, :float, :integer, :string]

  @valid_relationship_opts [:optional]

  @doc """
  Returns true if the given value is a valid value for the given attribute type and declaration options, or false otherwise.
  A nil value is valid only when the optional option is true.
  """
  @spec attribute_value_valid?(any, atom, T.opts()) :: boolean
  def attribute_value_valid?(value, type, opts \\ [])

  def attribute_value_valid?(nil, _type, opts), do: Keyword.get(opts, :optional) == true

  def attribute_value_valid?(value, :boolean, _opts), do: is_boolean(value)

  def attribute_value_valid?(value, :date, _opts), do: is_struct(value, Date)

  def attribute_value_valid?(value, :datetime, _opts), do: is_struct(value, DateTime)

  def attribute_value_valid?(value, :enum, opts),
    do: is_atom(value) and value in Keyword.fetch!(opts, :values)

  def attribute_value_valid?(value, :float, _opts), do: is_float(value)

  def attribute_value_valid?(value, :integer, _opts) do
    is_integer(value) and value >= @min_integer and value <= @max_integer
  end

  def attribute_value_valid?(value, :string, _opts), do: is_binary(value) and String.valid?(value)

  # Only the canonical lowercase 8-4-4-4-12 form is valid - the framework
  # generates and stores ids in that spelling, and the client tier compares ids
  # as strings, so any alternative spelling would match on one tier only.
  def attribute_value_valid?(value, :uuid, _opts) when is_binary(value) do
    String.match?(value, ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
  end

  def attribute_value_valid?(_value, :uuid, _opts), do: false

  @doc """
  Builds one error message describing every violation reported by validate/2, naming the entity type and, per violation, the attribute, the expectation, and the received value.
  """
  @spec error_message(module, %{atom => any}, list({atom, atom | {atom, any}})) :: String.t()
  def error_message(entity_type, data, errors) do
    descriptions = Enum.map_join(errors, "\n", &violation_description(data, &1))

    "invalid data for #{inspect(entity_type)}:\n#{descriptions}"
  end

  @doc """
  Validates the given data map against the given entity type's declared attributes.
  Returns :ok, or {:error, errors} where errors is a name-sorted list of {name, reason} pairs.
  Reasons: :required (a non-optional attribute is absent or nil), :unknown (an undeclared name), {:type, type} (a value not matching the attribute type), {:values, values} (an enum value outside the declared values), {:min, min} (a value below the declared minimum), {:max, max} (a value above the declared maximum), {:in, range} (an integer value outside the declared range), {:length, length} (a string not matching the declared exact length), {:min_length, min_length} (a string shorter than the declared minimum), {:max_length, max_length} (a string longer than the declared maximum), {:format, format} (a string not matching the declared pattern).
  String lengths count Unicode code points.
  Constraint options are checked only on type-valid values - a type violation suppresses the attribute's constraint checks.
  A non-optional attribute must be present regardless of its declared default - defaults are not applied here.
  An absent or nil optional attribute is valid.
  """
  @spec validate(module, %{atom => any}) :: :ok | {:error, list({atom, atom | {atom, any}})}
  def validate(entity_type, data) do
    attributes = entity_type.__attributes__()
    attribute_names = Enum.map(attributes, fn {name, _type, _opts} -> name end)

    unknown_errors =
      data
      |> Map.keys()
      |> Enum.reject(&(&1 in attribute_names))
      |> Enum.map(&{&1, :unknown})

    attribute_errors = Enum.flat_map(attributes, &attribute_data_errors(data, &1))

    case Enum.sort(unknown_errors ++ attribute_errors) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  Validates the given attribute declaration at compile time.
  Returns :ok, or raises Hologram.CompileError on the first violated rule (name, type, options, enum values, bounds, default).
  """
  @spec validate_attribute!(module, atom, any, T.opts()) :: :ok
  def validate_attribute!(module, name, type, opts) do
    validate_attribute_name!(module, name)
    validate_attribute_type!(module, name, type)
    validate_attribute_opts!(module, name, opts)
    validate_attribute_values!(module, name, type, opts)
    validate_attribute_bounds!(module, name, type, opts)
    validate_attribute_in!(module, name, type, opts)
    validate_attribute_lengths!(module, name, type, opts)
    validate_attribute_format!(module, name, type, opts)
    validate_attribute_default!(module, name, type, opts)
    validate_field_collision!(module, "attribute", name, [Atom.to_string(name)])
    :ok
  end

  @doc """
  Validates the given partial changes map against the given entity type's declared attributes.
  Returns :ok, or {:error, errors} in the validate/2 shape and reason vocabulary.
  Only present pairs are validated - absence is legal in a partial map. A nil value for a non-optional attribute reports :required - a nil value for an optional attribute is valid (clearing).
  """
  @spec validate_changes(module, %{atom => any}) ::
          :ok | {:error, list({atom, atom | {atom, any}})}
  def validate_changes(entity_type, changes) do
    attributes_by_name =
      Map.new(entity_type.__attributes__(), fn {name, type, opts} -> {name, {type, opts}} end)

    errors =
      changes
      |> Enum.flat_map(fn {name, value} ->
        case Map.fetch(attributes_by_name, name) do
          {:ok, {type, opts}} -> change_errors(name, value, type, opts)
          :error -> [{name, :unknown}]
        end
      end)
      |> Enum.sort()

    if errors == [], do: :ok, else: {:error, errors}
  end

  @doc """
  Validates the given data model as a whole, taking the list of all compiled entity type modules.

  Returns :ok, or raises Hologram.CompileError listing every relationship whose target is not an entity type module.
  This check is possible only after all entity type modules are compiled - relationship declarations verify the type shape alone, because the target module may not be compiled yet while the declaring module's body is executing.
  """
  @spec validate_model!(list(module)) :: :ok
  def validate_model!(entity_types) do
    violations =
      entity_types
      |> Enum.flat_map(&relationship_target_violations/1)
      |> Enum.sort()

    if violations != [] do
      descriptions =
        Enum.map_join(violations, "\n", fn {entity_type, name, target} ->
          "  * relationship #{inspect(name)} in #{inspect(entity_type)} targets #{inspect(target)}, which is not an entity type module"
        end)

      raise Hologram.CompileError, message: "invalid data model:\n#{descriptions}"
    end

    :ok
  end

  @doc """
  Validates the given relationship declaration at compile time.

  Returns :ok, or raises Hologram.CompileError on the first violated rule (name, type shape, options).
  The type is checked for shape only (an entity type module or a one-element list wrapping one) - whether it names an actual entity type module is not verified here, because the target module may not be compiled yet while the declaring module's body is executing.
  """
  @spec validate_relationship!(module, atom, any, T.opts()) :: :ok
  def validate_relationship!(module, name, type, opts) do
    validate_relationship_name!(module, name)
    validate_relationship_type!(module, name, type)
    validate_relationship_opts!(module, name, opts)
    validate_field_collision!(module, "relationship", name, relationship_field_names(name, type))
    :ok
  end

  defp attribute_data_errors(data, {name, type, opts}) do
    optional? = Keyword.get(opts, :optional) == true

    case Map.fetch(data, name) do
      {:ok, nil} ->
        if optional?, do: [], else: [{name, :required}]

      {:ok, value} ->
        value_errors(name, value, type, opts)

      :error ->
        if optional?, do: [], else: [{name, :required}]
    end
  end

  defp bound_errors(name, value, type, opts) do
    Enum.flat_map([:min, :max], &bound_key_errors(name, value, type, opts, &1))
  end

  defp bound_key_errors(name, value, type, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, bound} ->
        if bound_satisfied?(value, bound, key, type), do: [], else: [{name, {key, bound}}]

      :error ->
        []
    end
  end

  defp bound_requirement(:float), do: "must be a number"

  defp bound_requirement(type), do: "must match the attribute type #{inspect(type)}"

  defp bound_satisfied?(value, bound, :min, type), do: bounds_ordered?(bound, value, type)

  defp bound_satisfied?(value, bound, :max, type), do: bounds_ordered?(value, bound, type)

  defp bound_value_valid?(value, :float), do: is_number(value)

  defp bound_value_valid?(value, type), do: attribute_value_valid?(value, type, [])

  defp bounds_ordered?(min, max, :date), do: Date.compare(min, max) != :gt

  defp bounds_ordered?(min, max, :datetime), do: DateTime.compare(min, max) != :gt

  defp bounds_ordered?(min, max, _type), do: min <= max

  defp change_errors(name, nil, _type, opts) do
    if Keyword.get(opts, :optional) == true, do: [], else: [{name, :required}]
  end

  defp change_errors(name, value, type, opts), do: value_errors(name, value, type, opts)

  defp constraint_errors(name, value, type, opts) do
    bound_errors(name, value, type, opts) ++
      in_errors(name, value, opts) ++
      length_errors(name, value, opts) ++
      format_errors(name, value, opts)
  end

  defp declared_fields(module) do
    attribute_fields =
      module
      |> Module.get_attribute(:__attributes__)
      |> Enum.map(fn {name, _type, _opts} ->
        {Atom.to_string(name), "attribute #{inspect(name)}"}
      end)

    relationship_fields =
      module
      |> Module.get_attribute(:__relationships__)
      |> Enum.flat_map(fn {name, type, _opts} ->
        name
        |> relationship_field_names(type)
        |> Enum.map(&{&1, "relationship #{inspect(name)}"})
      end)

    attribute_fields ++ relationship_fields
  end

  defp format_errors(name, value, opts) do
    case Keyword.fetch(opts, :format) do
      {:ok, regex} ->
        if Regex.match?(regex, value), do: [], else: [{name, {:format, regex}}]

      :error ->
        []
    end
  end

  defp in_errors(name, value, opts) do
    case Keyword.fetch(opts, :in) do
      {:ok, range} ->
        if value in range, do: [], else: [{name, {:in, range}}]

      :error ->
        []
    end
  end

  defp length_errors(name, value, opts) do
    case Keyword.take(opts, [:length, :min_length, :max_length]) do
      [] ->
        []

      length_opts ->
        count = length(String.codepoints(value))
        Enum.flat_map(length_opts, &length_key_errors(name, count, &1))
    end
  end

  defp length_key_errors(name, count, {key, bound}) do
    if length_satisfied?(count, key, bound), do: [], else: [{name, {key, bound}}]
  end

  defp length_satisfied?(count, :length, bound), do: count == bound

  defp length_satisfied?(count, :min_length, bound), do: count >= bound

  defp length_satisfied?(count, :max_length, bound), do: count <= bound

  defp relationship_field_names(name, [_target]), do: [Atom.to_string(name)]

  defp relationship_field_names(name, _target), do: [Atom.to_string(name), "#{name}_id"]

  defp relationship_target([target]), do: target

  defp relationship_target(target), do: target

  defp relationship_target_violations(entity_type) do
    entity_type.__relationships__()
    |> Enum.map(fn {name, type, _opts} -> {name, relationship_target(type)} end)
    |> Enum.reject(fn {_name, target} -> Reflection.entity?(target) end)
    |> Enum.map(fn {name, target} -> {entity_type, name, target} end)
  end

  defp relationship_type_valid?(type) when is_atom(type), do: Reflection.alias?(type)

  defp relationship_type_valid?([type]), do: Reflection.alias?(type)

  defp relationship_type_valid?(_type), do: false

  defp requirement_description({:type, type}), do: "must be of type #{inspect(type)}"

  defp requirement_description({:values, values}), do: "must be one of #{inspect(values)}"

  defp requirement_description({:min, min}), do: "must be at least #{inspect(min)}"

  defp requirement_description({:max, max}), do: "must be at most #{inspect(max)}"

  defp requirement_description({:in, range}), do: "must be in #{inspect(range)}"

  defp requirement_description({:length, length}), do: "must be exactly #{length} characters"

  defp requirement_description({:min_length, min_length}),
    do: "must be at least #{min_length} characters"

  defp requirement_description({:max_length, max_length}),
    do: "must be at most #{max_length} characters"

  defp requirement_description({:format, format}), do: "must match #{inspect(format)}"

  defp validate_attribute_bounds!(module, name, type, opts) do
    Enum.each([:min, :max], &validate_bound_opt!(module, name, type, opts, &1))
    validate_bounds_order!(module, name, type, opts)
  end

  defp validate_attribute_default!(module, name, type, opts) do
    case Keyword.fetch(opts, :default) do
      {:ok, value} ->
        validate_default_value!(module, name, type, opts, value)

      :error ->
        :ok
    end
  end

  defp validate_attribute_format!(module, name, type, opts) do
    case Keyword.fetch(opts, :format) do
      {:ok, _value} when type != :string ->
        raise Hologram.CompileError,
          message:
            "format option not allowed for attribute #{inspect(name)} in #{inspect(module)} - the format option applies only to string attributes"

      {:ok, value} ->
        if not is_struct(value, Regex) do
          raise Hologram.CompileError,
            message:
              "invalid format option #{inspect(value)} for attribute #{inspect(name)} in #{inspect(module)} - the format option must be a Regex"
        end

      :error ->
        :ok
    end
  end

  defp validate_attribute_in!(module, name, type, opts) do
    case Keyword.fetch(opts, :in) do
      {:ok, _value} when type != :integer ->
        raise Hologram.CompileError,
          message:
            "in option not allowed for attribute #{inspect(name)} in #{inspect(module)} - the in option applies only to integer attributes"

      {:ok, value} ->
        validate_in_conflict!(module, name, opts)
        validate_in_range!(module, name, value)

      :error ->
        :ok
    end
  end

  defp validate_attribute_lengths!(module, name, type, opts) do
    Enum.each(
      [:length, :min_length, :max_length],
      &validate_length_opt!(module, name, type, opts, &1)
    )

    validate_length_conflict!(module, name, opts)
    validate_lengths_order!(module, name, opts)
  end

  defp validate_attribute_name!(module, name) do
    validate_declaration_name!(module, "attribute", name)
  end

  defp validate_attribute_opts!(module, name, opts) do
    validate_opts_shape!(module, "attribute", name, opts)
    validate_known_opts!(module, "attribute", name, opts, @valid_attribute_opts)
    validate_optional_opt!(module, "attribute", name, opts)
  end

  defp validate_attribute_type!(module, name, type) do
    if type not in @valid_attribute_types do
      valid_types = Enum.map_join(@valid_attribute_types, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "invalid type #{inspect(type)} for attribute #{inspect(name)} in #{inspect(module)} - valid attribute types are: #{valid_types}"
    end
  end

  defp validate_attribute_values!(module, name, :enum, opts) do
    case Keyword.fetch(opts, :values) do
      {:ok, values} ->
        validate_enum_values!(module, name, values)

      :error ->
        raise Hologram.CompileError,
          message:
            "missing values option for enum attribute #{inspect(name)} in #{inspect(module)} - enum attributes require a values option with a non-empty list of unique non-nil atoms"
    end
  end

  defp validate_attribute_values!(module, name, _type, opts) do
    if Keyword.has_key?(opts, :values) do
      raise Hologram.CompileError,
        message:
          "values option not allowed for attribute #{inspect(name)} in #{inspect(module)} - the values option applies only to enum attributes"
    end
  end

  defp validate_bound_opt!(module, name, type, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, _value} when type not in @bounded_attribute_types ->
        raise Hologram.CompileError,
          message:
            "#{key} option not allowed for attribute #{inspect(name)} in #{inspect(module)} - min and max options apply only to integer, float, date and datetime attributes"

      {:ok, value} ->
        if not bound_value_valid?(value, type) do
          raise Hologram.CompileError,
            message:
              "invalid #{key} option #{inspect(value)} for attribute #{inspect(name)} in #{inspect(module)} - the #{key} option #{bound_requirement(type)}"
        end

      :error ->
        :ok
    end
  end

  defp validate_bounds_order!(module, name, type, opts) do
    min = Keyword.get(opts, :min)
    max = Keyword.get(opts, :max)

    if min != nil and max != nil and not bounds_ordered?(min, max, type) do
      raise Hologram.CompileError,
        message:
          "conflicting min and max options for attribute #{inspect(name)} in #{inspect(module)} - min #{inspect(min)} must be less than or equal to max #{inspect(max)}"
    end

    :ok
  end

  defp validate_declaration_name!(module, kind, name) do
    if not is_atom(name) do
      raise Hologram.CompileError,
        message:
          "invalid name #{inspect(name)} used for #{kind} in #{inspect(module)} - declaration names must be atoms"
    end

    if name in @reserved_names do
      reserved_names = Enum.map_join(@reserved_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "reserved name #{inspect(name)} used for #{kind} in #{inspect(module)} - system attributes #{reserved_names} are managed automatically and can't be declared"
    end

    validate_name_uniqueness!(module, kind, name)
  end

  defp validate_default_constraints!(_module, _name, _type, _opts, nil), do: :ok

  defp validate_default_constraints!(module, name, type, opts, value) do
    case constraint_errors(name, value, type, opts) do
      [] ->
        :ok

      [{_name, {kind, constraint}} | _rest] ->
        raise Hologram.CompileError,
          message:
            "invalid default value #{inspect(value)} for attribute #{inspect(name)} in #{inspect(module)} - the default value doesn't satisfy the #{kind} option #{inspect(constraint)}"
    end
  end

  defp validate_default_value!(module, name, :enum, opts, value) do
    if not attribute_value_valid?(value, :enum, opts) do
      raise Hologram.CompileError,
        message:
          "invalid default value #{inspect(value)} for enum attribute #{inspect(name)} in #{inspect(module)} - the default value must be one of the declared values or nil when the attribute is optional"
    end
  end

  defp validate_default_value!(module, name, type, opts, value) do
    if not attribute_value_valid?(value, type, opts) do
      raise Hologram.CompileError,
        message:
          "invalid default value #{inspect(value)} for attribute #{inspect(name)} in #{inspect(module)} - the default value must match the attribute type #{inspect(type)}"
    end

    validate_default_constraints!(module, name, type, opts, value)
  end

  defp validate_enum_values!(module, name, values) do
    valid =
      is_list(values) and values != [] and
        Enum.all?(values, &(is_atom(&1) and not is_nil(&1))) and
        values == Enum.uniq(values)

    if not valid do
      raise Hologram.CompileError,
        message:
          "invalid values option #{inspect(values)} for enum attribute #{inspect(name)} in #{inspect(module)} - the values option must be a non-empty list of unique non-nil atoms"
    end
  end

  defp validate_field_collision!(module, kind, name, field_names) do
    declared = declared_fields(module)

    Enum.each(field_names, fn field_name ->
      case List.keyfind(declared, field_name, 0) do
        {_field_name, declaration} ->
          raise Hologram.CompileError,
            message:
              "#{kind} #{inspect(name)} in #{inspect(module)} derives entity field :#{field_name}, which collides with #{declaration} - every declaration must derive distinct fields"

        nil ->
          :ok
      end
    end)
  end

  defp validate_in_conflict!(module, name, opts) do
    if Keyword.has_key?(opts, :min) or Keyword.has_key?(opts, :max) do
      raise Hologram.CompileError,
        message:
          "conflicting options for attribute #{inspect(name)} in #{inspect(module)} - the in option can't be combined with the min and max options"
    end
  end

  defp validate_in_range!(module, name, value) do
    cond do
      not is_struct(value, Range) ->
        raise Hologram.CompileError,
          message:
            "invalid in option #{inspect(value)} for attribute #{inspect(name)} in #{inspect(module)} - the in option must be an integer Range"

      not (attribute_value_valid?(value.first, :integer) and
               attribute_value_valid?(value.last, :integer)) ->
        raise Hologram.CompileError,
          message:
            "invalid in option #{inspect(value)} for attribute #{inspect(name)} in #{inspect(module)} - the in option range endpoints must be valid integer attribute values"

      Range.size(value) == 0 ->
        raise Hologram.CompileError,
          message:
            "invalid in option #{inspect(value)} for attribute #{inspect(name)} in #{inspect(module)} - the in option range must not be empty"

      true ->
        :ok
    end
  end

  defp validate_known_opts!(module, kind, name, opts, valid_opts) do
    Enum.each(opts, fn {key, _value} ->
      if key not in valid_opts do
        valid_opts_list = Enum.map_join(valid_opts, ", ", &inspect/1)

        raise Hologram.CompileError,
          message:
            "unknown option #{inspect(key)} for #{kind} #{inspect(name)} in #{inspect(module)} - valid #{kind} options are: #{valid_opts_list}"
      end
    end)
  end

  defp validate_length_conflict!(module, name, opts) do
    if Keyword.has_key?(opts, :length) and
         (Keyword.has_key?(opts, :min_length) or Keyword.has_key?(opts, :max_length)) do
      raise Hologram.CompileError,
        message:
          "conflicting options for attribute #{inspect(name)} in #{inspect(module)} - the length option can't be combined with the min_length and max_length options"
    end
  end

  defp validate_length_opt!(module, name, type, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, _value} when type != :string ->
        raise Hologram.CompileError,
          message:
            "#{key} option not allowed for attribute #{inspect(name)} in #{inspect(module)} - length options apply only to string attributes"

      {:ok, value} ->
        if not (is_integer(value) and value >= 0) do
          raise Hologram.CompileError,
            message:
              "invalid #{key} option #{inspect(value)} for attribute #{inspect(name)} in #{inspect(module)} - the #{key} option must be a non-negative integer"
        end

      :error ->
        :ok
    end
  end

  defp validate_lengths_order!(module, name, opts) do
    min = Keyword.get(opts, :min_length)
    max = Keyword.get(opts, :max_length)

    if min != nil and max != nil and min > max do
      raise Hologram.CompileError,
        message:
          "conflicting min_length and max_length options for attribute #{inspect(name)} in #{inspect(module)} - min_length #{inspect(min)} must be less than or equal to max_length #{inspect(max)}"
    end

    :ok
  end

  defp validate_name_uniqueness!(module, kind, name) do
    declarations =
      Module.get_attribute(module, :__attributes__) ++
        Module.get_attribute(module, :__relationships__)

    declared_names = Enum.map(declarations, fn {declared_name, _type, _opts} -> declared_name end)

    if name in declared_names do
      raise Hologram.CompileError,
        message:
          "duplicate name #{inspect(name)} used for #{kind} in #{inspect(module)} - attribute and relationship names share one namespace and must be unique"
    end
  end

  defp validate_optional_opt!(module, kind, name, opts) do
    case Keyword.fetch(opts, :optional) do
      {:ok, value} when not is_boolean(value) ->
        raise Hologram.CompileError,
          message:
            "invalid optional option #{inspect(value)} for #{kind} #{inspect(name)} in #{inspect(module)} - the optional option must be true or false"

      _fetch_result ->
        :ok
    end
  end

  defp validate_opts_shape!(module, kind, name, opts) do
    if not Keyword.keyword?(opts) do
      raise Hologram.CompileError,
        message:
          "invalid options #{inspect(opts)} for #{kind} #{inspect(name)} in #{inspect(module)} - options must be a keyword list"
    end
  end

  defp validate_relationship_name!(module, name) do
    validate_declaration_name!(module, "relationship", name)
  end

  defp validate_relationship_opts!(module, name, opts) do
    validate_opts_shape!(module, "relationship", name, opts)
    validate_known_opts!(module, "relationship", name, opts, @valid_relationship_opts)
    validate_optional_opt!(module, "relationship", name, opts)
  end

  defp validate_relationship_type!(module, name, type) do
    if not relationship_type_valid?(type) do
      raise Hologram.CompileError,
        message:
          "invalid type #{inspect(type)} for relationship #{inspect(name)} in #{inspect(module)} - the relationship type must be an entity type module (to-one) or a one-element list wrapping an entity type module (to-many)"
    end
  end

  defp value_errors(name, value, :enum, opts) do
    values = Keyword.fetch!(opts, :values)

    if is_atom(value) and value in values do
      []
    else
      [{name, {:values, values}}]
    end
  end

  defp value_errors(name, value, type, opts) do
    if attribute_value_valid?(value, type) do
      constraint_errors(name, value, type, opts)
    else
      [{name, {:type, type}}]
    end
  end

  defp violation_description(_data, {name, :required}) do
    "  * attribute #{inspect(name)} is required"
  end

  defp violation_description(_data, {name, :unknown}) do
    "  * #{inspect(name)} is not a declared attribute"
  end

  defp violation_description(data, {name, reason}) do
    "  * attribute #{inspect(name)} #{requirement_description(reason)}, got: #{inspect(Map.get(data, name))}"
  end
end
