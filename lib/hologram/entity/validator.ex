defmodule Hologram.Entity.Validator do
  @moduledoc false

  alias Hologram.Commons.Types, as: T
  alias Hologram.Reflection

  # Postgres int8 column bounds
  @max_integer 9_223_372_036_854_775_807
  @min_integer -9_223_372_036_854_775_808

  @reserved_names [:created_at, :id, :updated_at]

  @valid_attribute_opts [:default, :optional, :values]

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

  @doc """
  Validates the given data map against the given entity type's declared attributes.
  Returns :ok, or {:error, errors} where errors is a name-sorted list of {name, reason} tuples with reason being :invalid, :missing or :unknown.
  A non-optional attribute must be present regardless of its declared default - defaults are not applied here.
  An absent optional attribute is valid.
  """
  @spec validate(module, %{atom => any}) :: :ok | {:error, list({atom, atom})}
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
  Returns :ok, or raises Hologram.CompileError on the first violated rule (name, type, options, enum values, default).
  """
  @spec validate_attribute!(module, atom, any, T.opts()) :: :ok
  def validate_attribute!(module, name, type, opts) do
    validate_attribute_name!(module, name)
    validate_attribute_type!(module, name, type)
    validate_attribute_opts!(module, name, opts)
    validate_attribute_values!(module, name, type, opts)
    validate_attribute_default!(module, name, type, opts)
    :ok
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
    :ok
  end

  defp attribute_data_errors(data, {name, type, opts}) do
    case Map.fetch(data, name) do
      {:ok, value} ->
        if attribute_value_valid?(value, type, opts), do: [], else: [{name, :invalid}]

      :error ->
        if Keyword.get(opts, :optional) == true, do: [], else: [{name, :missing}]
    end
  end

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

  defp validate_attribute_default!(module, name, type, opts) do
    case Keyword.fetch(opts, :default) do
      {:ok, value} ->
        validate_default_value!(module, name, type, opts, value)

      :error ->
        :ok
    end
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
end
