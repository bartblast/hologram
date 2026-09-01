defmodule Hologram.Entity.Validator do
  @moduledoc false

  alias Hologram.Commons.Types, as: T
  alias Hologram.DB.Codec
  alias Hologram.Entity
  alias Hologram.Reflection

  @bounded_attribute_types [:date, :datetime, :float, :integer, :time]

  # Postgres enum label limit
  @max_enum_label_bytes 63

  # Postgres int8 column bounds
  @max_integer 9_223_372_036_854_775_807
  @min_integer -9_223_372_036_854_775_808

  @policy_option_names [:to, :via]

  @reserved_names [:created_at, :id, :updated_at]

  # The two operations that may name the role they cover
  @role_operations [:grant_role, :revoke_role]

  # The most bytes a unique string may hold. Its unique index is a btree over the raw column, and
  # PostgreSQL caps a btree entry at 2704 bytes on its default 8 KB page - minus the 8-byte item
  # header and the 4-byte varlena header leaves 2692 for the value. Measured rather than derived:
  # 2692 incompressible bytes always fit, 2693 never do. The engine compresses entries, so a longer
  # repetitive value would fit - but a rule a developer can hold has to be about length alone.
  @unique_string_max_bytes 2692

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
    :server_only,
    :unique,
    :values
  ]

  @valid_attribute_types [
    :boolean,
    :date,
    :datetime,
    :enum,
    :float,
    :integer,
    :string,
    :time,
    :uuid
  ]

  @valid_relationship_opts [:optional]

  @valid_role_opts [:extends, :granted_to]

  @valid_use_opts [:user]

  @valid_use_role_opts [:extends]

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

  def attribute_value_valid?(value, :time, _opts), do: is_struct(value, Time)

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
    descriptions =
      Enum.map_join(errors, "\n", &violation_description(entity_type, data, &1))

    "invalid data for #{inspect(entity_type)}:\n#{descriptions}"
  end

  @doc """
  Validates the given data map against the given entity type's declared attributes.
  Returns :ok, or {:error, errors} where errors is a name-sorted list of {name, reason} pairs.
  Reasons: :required (a non-optional attribute is absent or nil), :unknown (an undeclared name), {:type, type} (a value not matching the attribute type), {:values, values} (an enum value outside the declared values), {:min, min} (a value below the declared minimum), {:max, max} (a value above the declared maximum), {:in, range} (an integer value outside the declared range), {:length, length} (a string not matching the declared exact length), {:min_length, min_length} (a string shorter than the declared minimum), {:max_length, max_length} (a string longer than the declared maximum), {:format, format} (a string not matching the declared pattern), {:max_bytes, max_bytes} (a unique string holding more bytes than its index can carry).
  String lengths count Unicode code points.
  Constraint options are checked only on type-valid values - a type violation suppresses the attribute's constraint checks.
  A non-optional attribute must be present regardless of its declared default - defaults are not applied here.
  An absent or nil optional attribute is valid.
  To-one reference fields (`<name>_id`) validate alongside attributes: a non-optional reference must be present and non-nil (:required), and a present value must be a canonical entity id ({:type, :uuid}).
  """
  @spec validate(module, %{atom => any}) :: :ok | {:error, list({atom, atom | {atom, any}})}
  def validate(entity_type, data) do
    attributes = entity_type.__attributes__()
    attribute_names = Enum.map(attributes, fn {name, _type, _opts} -> name end)
    references = reference_definitions(entity_type)
    reference_names = Enum.map(references, fn {field, _optional?} -> field end)
    known_names = attribute_names ++ reference_names

    unknown_errors =
      data
      |> Map.keys()
      |> Enum.reject(&(&1 in known_names))
      |> Enum.map(&{&1, :unknown})

    attribute_errors = Enum.flat_map(attributes, &attribute_data_errors(data, &1))
    reference_errors = Enum.flat_map(references, &reference_data_errors(data, &1))

    case Enum.sort(unknown_errors ++ attribute_errors ++ reference_errors) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  Validates the given policy declaration at compile time.

  Returns :ok, or raises Hologram.CompileError on the first violated rule (operation, spec shape).
  Predicates and the to and via options are validated separately, at the whole-model point - they reference attributes, roles and relationships of entity types that may not be compiled yet.
  """
  @spec validate_allow!(module, Entity.operation(), T.opts()) :: :ok
  def validate_allow!(module, operation, spec) do
    validate_operation_shape!(module, operation)
    validate_opts_shape!(module, "allow", operation, spec)

    Enum.each(@policy_option_names, &validate_policy_option_value!(module, operation, spec, &1))
    validate_to_opt_shape!(module, operation, spec)

    :ok
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
  To-one reference field pairs (`<name>_id`) follow the same rules: nil is valid only for an optional relationship, and a present value must be a canonical entity id.
  """
  @spec validate_changes(module, %{atom => any}) ::
          :ok | {:error, list({atom, atom | {atom, any}})}
  def validate_changes(entity_type, changes) do
    attributes_by_name =
      Map.new(entity_type.__attributes__(), fn {name, type, opts} -> {name, {type, opts}} end)

    references_by_field =
      entity_type
      |> reference_definitions()
      |> Map.new()

    errors =
      changes
      |> Enum.flat_map(fn {name, value} ->
        cond do
          Map.has_key?(attributes_by_name, name) ->
            {type, opts} = attributes_by_name[name]
            change_errors(name, value, type, opts)

          Map.has_key?(references_by_field, name) ->
            reference_change_errors(name, value, references_by_field[name])

          true ->
            [{name, :unknown}]
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

  @doc """
  Validates the given role declaration at compile time.

  Returns :ok, or raises Hologram.CompileError on the first violated rule (name, option keys, creator and scope options).
  The extends option is checked separately, because its targets may be declared further down the module body.
  """
  @spec validate_role!(module, atom, T.opts()) :: :ok
  def validate_role!(module, name, opts) do
    validate_role_name!(module, name)
    validate_role_opts!(module, name, opts)
    :ok
  end

  @doc """
  Validates the role declarations of the given module as a whole, after its body has executed.

  Returns :ok, or raises Hologram.CompileError on the first violated rule (extends option shape, extends targets, extension cycles).
  Role extension is checked here rather than per declaration, so that a role can extend one declared further down the module body.
  """
  @spec validate_roles!(module) :: :ok
  def validate_roles!(module) do
    roles =
      module
      |> Module.get_attribute(:__roles__)
      |> Enum.sort()

    # The MERGED roles are the graph - a cycle is a property of the composed picture. The RAW
    # declarations are what the messages read, because only they know which module wrote which
    # extends target; a merged entry has lost that.
    declarations =
      module
      |> Module.get_attribute(:__role_declarations__)
      |> Enum.reverse()

    declared_names = Enum.map(roles, fn {name, _opts} -> name end)

    Enum.each(declarations, fn {name, opts, source} ->
      validate_extends_opt!(module, name, opts, declared_names, source)
    end)

    validate_role_extension_cycles!(module, roles, declarations)

    :ok
  end

  @doc """
  Validates that entities of the given type are written through the general write surface.

  Returns :ok, or raises ArgumentError for entity types the framework writes itself.
  """
  @spec validate_writable!(module) :: :ok
  def validate_writable!(Hologram.Auth.RoleGrant) do
    raise ArgumentError, "role grants are written only through grant_role/revoke_role"
  end

  def validate_writable!(_entity_type), do: :ok

  @doc """
  Validates the options given to the use Hologram.Job directive at compile time.

  Returns :ok, or raises Hologram.CompileError on the first violated rule (options shape, option keys).
  """
  @spec validate_use_job_opts!(module, T.opts()) :: :ok
  def validate_use_job_opts!(module, opts) do
    if not Keyword.keyword?(opts) do
      raise Hologram.CompileError,
        message:
          "invalid options #{inspect(opts)} for use Hologram.Job in #{inspect(module)} - options must be a keyword list"
    end

    Enum.each(opts, fn {key, _value} ->
      raise Hologram.CompileError,
        message:
          "unknown option #{inspect(key)} for use Hologram.Job in #{inspect(module)} - use Hologram.Job takes no options"
    end)

    :ok
  end

  @doc """
  Validates the options given to the use Hologram.Entity directive at compile time.

  Returns :ok, or raises Hologram.CompileError on the first violated rule (options shape, option keys, user option).
  """
  @spec validate_use_opts!(module, T.opts()) :: :ok
  def validate_use_opts!(module, opts) do
    if not Keyword.keyword?(opts) do
      raise Hologram.CompileError,
        message:
          "invalid options #{inspect(opts)} for use Hologram.Entity in #{inspect(module)} - options must be a keyword list"
    end

    validate_use_opt_keys!(module, opts)
    validate_user_opt!(module, opts)

    :ok
  end

  @doc """
  Validates the options given to the use Hologram.Role directive at compile time.

  Returns :ok, or raises Hologram.CompileError on the first violated rule (options shape, option keys).
  """
  @spec validate_use_role_opts!(module, T.opts()) :: :ok
  def validate_use_role_opts!(module, opts) do
    if not Keyword.keyword?(opts) do
      raise Hologram.CompileError,
        message:
          "invalid options #{inspect(opts)} for use Hologram.Role in #{inspect(module)} - options must be a keyword list"
    end

    Enum.each(opts, fn {key, _value} ->
      if key not in @valid_use_role_opts do
        valid_opts = Enum.map_join(@valid_use_role_opts, ", ", &inspect/1)

        raise Hologram.CompileError,
          message:
            "unknown option #{inspect(key)} for use Hologram.Role in #{inspect(module)} - valid options are: #{valid_opts}"
      end
    end)

    :ok
  end

  @doc """
  Builds the description of a single violation reported by validate/2 - one line naming the attribute or reference, the expectation, and the received value, in the bulleted form error_message/3 renders.
  """
  @spec violation_description(module, %{atom => any}, {atom, atom | {atom, any}}) :: String.t()
  def violation_description(entity_type, data, error) do
    violation_line(reference_field_names(entity_type), data, error)
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

  defp bounds_ordered?(min, max, :time), do: Time.compare(min, max) != :gt

  defp bounds_ordered?(min, max, _type), do: min <= max

  # Rotates the cycle to start at its alphabetically first role, so that the same cycle
  # is always reported with the same hop order regardless of where the traversal entered it.
  defp canonicalize_role_cycle(cycle) do
    start_index =
      cycle
      |> Enum.with_index()
      |> Enum.min_by(fn {name, _index} -> name end)
      |> elem(1)

    {hops_before_start, hops_from_start} = Enum.split(cycle, start_index)
    hops_from_start ++ hops_before_start
  end

  defp change_errors(name, nil, _type, opts) do
    if Keyword.get(opts, :optional) == true, do: [], else: [{name, :required}]
  end

  defp change_errors(name, value, type, opts), do: value_errors(name, value, type, opts)

  defp constraint_errors(name, value, type, opts) do
    bound_errors(name, value, type, opts) ++
      in_errors(name, value, opts) ++
      length_errors(name, value, opts) ++
      format_errors(name, value, opts) ++
      unique_bytes_errors(name, value, type, opts)
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

  defp describe_role_cycle([first_name | _later_hops] = cycle, declarations, module) do
    # Each hop is paired with the hop it extends: the cycle rotated by one, so the last hop's
    # target wraps back to the first.
    targets = Enum.slide(cycle, 0, length(cycle) - 1)

    hops =
      cycle
      |> Enum.zip(targets)
      |> Enum.map_join(" -> ", &describe_role_cycle_hop(&1, declarations, module))

    "  * #{hops} -> #{inspect(first_name)}"
  end

  # A hop is annotated with the policies whose declaration of it carries the extends target the
  # cycle follows next - so a cycle no single module commits still names the files that formed it.
  # A hop the entity type declared itself reads unannotated, as it always did.
  defp describe_role_cycle_hop({name, target}, declarations, module) do
    sources =
      declarations
      |> Enum.filter(fn {declared_name, opts, _source} ->
        declared_name == name and target in List.wrap(opts[:extends])
      end)
      |> Enum.map(fn {_name, _opts, source} -> source end)
      |> Enum.uniq()

    case sources -- [module] do
      [] -> inspect(name)
      policies -> "#{inspect(name)} (from #{Enum.map_join(policies, ", ", &inspect/1)})"
    end
  end

  defp extends_value_valid?(value) when is_atom(value) and not is_nil(value), do: true

  defp extends_value_valid?([_first_target | _later_targets] = value),
    do: Enum.all?(value, &is_atom/1)

  defp extends_value_valid?(_value), do: false

  # Depth-first traversal over role extension edges. The path holds the roles visited on the way
  # to the current one (most recent first) - reaching a role already on the path closes a cycle.
  # Fully explored roles are marked visited and never re-entered, so each cycle is reported once.
  defp find_role_extension_cycles(name, path, edges, {cycles, visited}) do
    if MapSet.member?(visited, name) do
      {cycles, visited}
    else
      {cycles, visited} =
        edges
        |> Map.get(name, [])
        |> Enum.reduce({cycles, visited}, fn target, acc ->
          follow_role_extension_edge(name, target, path, edges, acc)
        end)

      {cycles, MapSet.put(visited, name)}
    end
  end

  # Closes a cycle when the target is already on the path, descends into the target otherwise.
  defp follow_role_extension_edge(name, target, path, edges, {cycles, visited}) do
    new_path = [name | path]

    if target in new_path do
      {hops_beyond_target, [target_hop | _earlier_hops]} =
        Enum.split_while(new_path, &(&1 != target))

      cycle = [target_hop | Enum.reverse(hops_beyond_target)]

      {[cycle | cycles], visited}
    else
      find_role_extension_cycles(target, new_path, edges, {cycles, visited})
    end
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

  defp reference_change_errors(field, nil, optional?) do
    if optional?, do: [], else: [{field, :required}]
  end

  defp reference_change_errors(field, value, _optional?) do
    if attribute_value_valid?(value, :uuid), do: [], else: [{field, {:type, :uuid}}]
  end

  defp reference_data_errors(data, {field, optional?}) do
    case Map.fetch(data, field) do
      {:ok, nil} ->
        if optional?, do: [], else: [{field, :required}]

      {:ok, value} ->
        if attribute_value_valid?(value, :uuid), do: [], else: [{field, {:type, :uuid}}]

      :error ->
        if optional?, do: [], else: [{field, :required}]
    end
  end

  defp reference_definitions(entity_type) do
    entity_type.__relationships__()
    |> Enum.reject(fn {_name, type, _opts} -> is_list(type) end)
    |> Enum.map(fn {name, _type, opts} ->
      {String.to_existing_atom("#{name}_id"), Keyword.get(opts, :optional) == true}
    end)
  end

  defp reference_field_names(entity_type) do
    entity_type
    |> reference_definitions()
    |> Enum.map(fn {field, _optional?} -> field end)
  end

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

  defp requirement_description({:max_bytes, max_bytes}),
    do: "must hold at most #{max_bytes} bytes (the most its unique index can carry)"

  defp role_extension_edges(roles) do
    Map.new(roles, fn {name, opts} -> {name, List.wrap(Keyword.get(opts, :extends, []))} end)
  end

  # Only a unique string carries the bound - it is its index's, not the type's, and it is checked in
  # bytes, not code points, because that is what the index stores.
  defp unique_bytes_errors(name, value, :string, opts) do
    if Keyword.get(opts, :unique) == true and byte_size(value) > @unique_string_max_bytes do
      [{name, {:max_bytes, @unique_string_max_bytes}}]
    else
      []
    end
  end

  defp unique_bytes_errors(_name, _value, _type, _opts), do: []

  defp validate_attribute_bounds!(module, name, type, opts) do
    Enum.each([:min, :max], &validate_bound_opt!(module, name, type, opts, &1))
    validate_bounds_order!(module, name, type, opts)
  end

  defp validate_attribute_default!(module, name, type, opts) do
    case Keyword.fetch(opts, :default) do
      {:ok, value} ->
        validate_unique_default!(module, name, opts, value)
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
    validate_policy_option_name!(module, name)
  end

  defp validate_attribute_opts!(module, name, opts) do
    validate_opts_shape!(module, "attribute", name, opts)
    validate_known_opts!(module, "attribute", name, opts, @valid_attribute_opts)
    validate_optional_opt!(module, "attribute", name, opts)
    validate_server_only_opt!(module, name, opts)
    validate_unique_opt!(module, name, opts)
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
            "#{key} option not allowed for attribute #{inspect(name)} in #{inspect(module)} - min and max options apply only to integer, float, date, datetime and time attributes"

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
    validate_name_type!(module, kind, name)

    if name in @reserved_names do
      reserved_names = Enum.map_join(@reserved_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "reserved name #{inspect(name)} used for #{kind} in #{inspect(module)} - system attributes #{reserved_names} are managed automatically and can't be declared"
    end

    # The one field every entity struct carries that no declaration puts there.
    if name == :__meta__ do
      raise Hologram.CompileError,
        message:
          "reserved name #{inspect(name)} used for #{kind} in #{inspect(module)} - it holds the framework's own metadata on every entity struct and can't be declared"
    end

    # The seam every physical name the framework derives carries - the sort-key companion
    # `<attribute>_$sort`, the revisions column `$revisions`, the index and constraint names. It is
    # what lets a declaration take any word at all without colliding with one of ours, and that
    # holds only while nothing declared can spell it. Refused here rather than where the collision
    # would be found: the mapper derives names at boot, so the same mistake caught there takes the
    # supervision tree down naming neither the module nor the declaration.
    carries_seam? =
      name
      |> Atom.to_string()
      |> String.contains?("$")

    if carries_seam? do
      raise Hologram.CompileError,
        message:
          "invalid name #{inspect(name)} used for #{kind} in #{inspect(module)} - $ is reserved for the physical names the framework derives, so a declared name can't contain it"
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

  # Postgres caps enum labels at 63 bytes and silently truncates longer ones - a truncated
  # label would no longer decode back to the value it was stored for.
  defp validate_enum_label_length!(module, kind, value) do
    label = Codec.encode(value, :enum)
    label_size = byte_size(label)

    if label_size > @max_enum_label_bytes do
      raise Hologram.CompileError,
        message:
          "#{kind} #{inspect(value)} in #{inspect(module)} is too long to store (#{label_size} bytes, limit #{@max_enum_label_bytes}) - shorten it"
    end
  end

  # Stored enum labels distinguish modules from plain atoms by their first character, so a
  # plain atom starting uppercase would decode back as a module.
  defp validate_lowercase_atom!(module, kind, value) do
    label = Codec.encode(value, :enum)

    if not Reflection.alias?(value) and not String.match?(label, ~r/^[a-z_]/) do
      raise Hologram.CompileError,
        message:
          "invalid #{kind} #{inspect(value)} in #{inspect(module)} - #{kind}s that are not modules must begin with a lowercase letter or an underscore"
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

    Enum.each(values, fn value ->
      validate_lowercase_atom!(module, "enum value", value)
      validate_enum_label_length!(module, "enum value", value)
    end)
  end

  # Twin of Hologram.Policy.Validator's location/2 - keep the two message shapes in step.
  defp location(module, module), do: inspect(module)

  defp location(module, source), do: "#{inspect(module)}, taken from #{inspect(source)}"

  defp validate_extends_opt!(module, name, opts, declared_names, source) do
    case Keyword.fetch(opts, :extends) do
      {:ok, value} ->
        location = location(module, source)

        if not extends_value_valid?(value) do
          raise Hologram.CompileError,
            message:
              "invalid extends option #{inspect(value)} for role #{inspect(name)} in #{location} - the extends option must be a role name or a non-empty list of role names"
        end

        value
        |> List.wrap()
        |> Enum.each(&validate_extends_target!(name, &1, declared_names, location))

      :error ->
        :ok
    end
  end

  defp validate_extends_target!(name, target, declared_names, location) do
    if target not in declared_names do
      declared_roles = Enum.map_join(declared_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "unknown role #{inspect(target)} in the extends option of role #{inspect(name)} in #{location} - declared roles are: #{declared_roles}"
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

  defp validate_granted_to_opt!(module, name, opts) do
    case Keyword.fetch(opts, :granted_to) do
      {:ok, value} when value != :creator and value != nil ->
        raise Hologram.CompileError,
          message:
            "invalid granted_to option #{inspect(value)} for role #{inspect(name)} in #{inspect(module)} - the granted_to option must be :creator or nil"

      _fetch_result ->
        :ok
    end
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

  defp validate_name_type!(module, kind, name) do
    if not is_atom(name) do
      raise Hologram.CompileError,
        message:
          "invalid name #{inspect(name)} used for #{kind} in #{inspect(module)} - declaration names must be atoms"
    end
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

  # The shape is structural, so it is checked where it is written - whether the named roles are
  # declared is checked at the whole-model point, since roles are compiled after the policy lines.
  defp validate_operation_shape!(_module, operation) when is_atom(operation), do: :ok

  defp validate_operation_shape!(module, {:read_roles, _roles} = operation) do
    raise Hologram.CompileError,
      message:
        "invalid operation #{inspect(operation)} used for allow in #{inspect(module)} - :read_roles takes no role, it reads the whole set and is declared bare"
  end

  defp validate_operation_shape!(module, operation) do
    if not role_operation_valid?(operation) do
      raise Hologram.CompileError,
        message:
          "invalid operation #{inspect(operation)} used for allow in #{inspect(module)} - a policy operation is an atom, or {:grant_role, role} / {:revoke_role, role} naming a declared role or a list of them"
    end

    :ok
  end

  defp validate_opts_shape!(module, kind, name, opts) do
    if not Keyword.keyword?(opts) do
      raise Hologram.CompileError,
        message:
          "invalid options #{inspect(opts)} for #{kind} #{inspect(name)} in #{inspect(module)} - options must be a keyword list"
    end
  end

  # On an allow line every key that is not an option is a predicate naming an attribute, so an
  # attribute named after an option could never be reached in predicate position.
  defp validate_policy_option_name!(module, name) do
    if name in @policy_option_names do
      policy_option_names = Enum.map_join(@policy_option_names, " and ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "reserved name #{inspect(name)} used for attribute in #{inspect(module)} - #{policy_option_names} are allow line options and can't be attribute names"
    end
  end

  # An option written as nil is indistinguishable from an absent one once the declaration is
  # stored, and both compile to a rule granting through no reference at all - which is what a
  # bare allow line means, so the mistake would silently widen the rule.
  defp validate_policy_option_value!(module, operation, spec, key) do
    if Keyword.has_key?(spec, key) and is_nil(Keyword.fetch!(spec, key)) do
      raise Hologram.CompileError,
        message:
          "invalid #{key} option nil for allow #{inspect(operation)} in #{inspect(module)} - omit the option instead"
    end

    :ok
  end

  # The shape is structural, so it is checked where it is written - the references themselves
  # are checked at the whole-model point, against reflection that does not exist yet here.
  defp validate_to_opt_shape!(module, operation, spec) do
    case Keyword.fetch(spec, :to) do
      {:ok, to} ->
        if not to_value_valid?(to) do
          raise Hologram.CompileError,
            message:
              "invalid to option #{inspect(to)} for allow #{inspect(operation)} in #{inspect(module)} - the to option must be a role name, a {module, role} or {relationship, role} tuple, or a non-empty list of them"
        end

      :error ->
        :ok
    end
  end

  defp role_operation_valid?({name, role}) when name in @role_operations and is_atom(role),
    do: true

  defp role_operation_valid?({name, [_first_role | _later_roles] = roles})
       when name in @role_operations,
       do: Enum.all?(roles, &is_atom/1)

  defp role_operation_valid?(_operation), do: false

  defp to_reference_valid?(value) when is_atom(value), do: true

  defp to_reference_valid?({reference, role_name}) when is_atom(reference) and is_atom(role_name),
    do: true

  defp to_reference_valid?(_value), do: false

  defp to_value_valid?([_first_reference | _later_references] = value),
    do: Enum.all?(value, &to_reference_valid?/1)

  defp to_value_valid?(value), do: to_reference_valid?(value)

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

  defp validate_role_extension_cycles!(module, roles, declarations) do
    edges = role_extension_edges(roles)

    {cycles, _visited} =
      edges
      |> Map.keys()
      |> Enum.reduce({[], MapSet.new()}, fn name, acc ->
        find_role_extension_cycles(name, [], edges, acc)
      end)

    if cycles != [] do
      descriptions =
        cycles
        |> Enum.map(&canonicalize_role_cycle/1)
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.map_join("\n", &describe_role_cycle(&1, declarations, module))

      raise Hologram.CompileError,
        message:
          "cyclic role extension in #{inspect(module)} - a role can't extend itself, directly or transitively:\n#{descriptions}"
    end
  end

  defp validate_role_name!(module, name) do
    validate_name_type!(module, "role", name)
    validate_lowercase_atom!(module, "role name", name)
    validate_enum_label_length!(module, "role name", name)
  end

  defp validate_role_opts!(module, name, opts) do
    validate_opts_shape!(module, "role", name, opts)
    validate_scope_opt_removed!(module, name, opts)
    validate_known_opts!(module, "role", name, opts, @valid_role_opts)
    validate_granted_to_opt!(module, name, opts)
  end

  defp validate_scope_opt_removed!(module, name, opts) do
    if Keyword.has_key?(opts, :scope) do
      raise Hologram.CompileError,
        message:
          "scope option for role #{inspect(name)} in #{inspect(module)} - the scope option was removed, define global roles as modules with use Hologram.Role"
    end

    :ok
  end

  defp validate_server_only_opt!(module, name, opts) do
    case Keyword.fetch(opts, :server_only) do
      {:ok, value} when not is_boolean(value) ->
        raise Hologram.CompileError,
          message:
            "invalid server_only option #{inspect(value)} for attribute #{inspect(name)} in #{inspect(module)} - the server_only option must be true or false"

      _fetch_result ->
        :ok
    end
  end

  defp validate_unique_opt!(module, name, opts) do
    case Keyword.fetch(opts, :unique) do
      {:ok, value} when not is_boolean(value) ->
        raise Hologram.CompileError,
          message:
            "invalid unique option #{inspect(value)} for attribute #{inspect(name)} in #{inspect(module)} - the unique option must be true or false"

      _fetch_result ->
        :ok
    end
  end

  # A default is one value for every row that omits the attribute, so at most one such row could
  # ever be stored - the rest meet the unique index. Refused where it is written rather than at the
  # second insert, where nothing points back at the declaration. A nil default is the absence of
  # one, and nulls stay distinct, so it passes.
  defp validate_unique_default!(_module, _name, _opts, nil), do: :ok

  defp validate_unique_default!(module, name, opts, value) do
    if Keyword.get(opts, :unique) == true do
      raise Hologram.CompileError,
        message:
          "invalid default value #{inspect(value)} for unique attribute #{inspect(name)} in #{inspect(module)} - a default is one value for every row that omits the attribute, so a unique attribute can't have one"
    end

    :ok
  end

  defp validate_use_opt_keys!(module, opts) do
    Enum.each(opts, fn {key, _value} ->
      if key not in @valid_use_opts do
        valid_opts = Enum.map_join(@valid_use_opts, ", ", &inspect/1)

        raise Hologram.CompileError,
          message:
            "unknown option #{inspect(key)} for use Hologram.Entity in #{inspect(module)} - valid options are: #{valid_opts}"
      end
    end)
  end

  defp validate_user_opt!(module, opts) do
    case Keyword.fetch(opts, :user) do
      {:ok, value} when value != true ->
        raise Hologram.CompileError,
          message:
            "invalid user option #{inspect(value)} for use Hologram.Entity in #{inspect(module)} - the user option must be true"

      _fetch_result ->
        :ok
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

  defp violation_line(reference_names, _data, {name, :required}) do
    kind_word = if name in reference_names, do: "reference", else: "attribute"

    "  * #{kind_word} #{inspect(name)} is required"
  end

  defp violation_line(_reference_names, _data, {name, :unknown}) do
    "  * #{inspect(name)} is not a declared attribute or to-one reference"
  end

  # A field the data does not hold has no received value to show - a moved attribute is judged on
  # the value the statement left, which the caller never held.
  defp violation_line(reference_names, data, {name, reason}) do
    cond do
      name in reference_names ->
        "  * reference #{inspect(name)} must be a valid entity id, got: #{inspect(Map.get(data, name))}"

      Map.has_key?(data, name) ->
        "  * attribute #{inspect(name)} #{requirement_description(reason)}, got: #{inspect(data[name])}"

      true ->
        "  * attribute #{inspect(name)} #{requirement_description(reason)}"
    end
  end
end
