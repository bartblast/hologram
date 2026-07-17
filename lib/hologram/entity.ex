defmodule Hologram.Entity do
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.AST
  alias Hologram.Entity

  @reserved_names [:created_at, :id, :updated_at]

  @valid_attr_opts [:default, :optional, :values]

  @valid_attr_types [:boolean, :date, :datetime, :enum, :float, :integer, :string]

  @valid_relationship_opts [:optional]

  defmacro __using__(_opts) do
    [
      quote do
        import Hologram.Entity,
          only: [attr: 2, attr: 3, relationship: 2, relationship: 3]

        @before_compile Entity

        @doc """
        Returns true to indicate that the callee module is an entity type module (has "use Hologram.Entity" directive).

        ## Examples

            iex> __is_hologram_entity__()
            true
        """
        @spec __is_hologram_entity__() :: boolean
        def __is_hologram_entity__, do: true
      end,
      register_attrs_accumulator(),
      register_relationships_accumulator()
    ]
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc """
      Returns the list of attribute definitions for the compiled entity type, sorted by attribute name.
      """
      @spec __attrs__() :: list({atom, atom, keyword})
      def __attrs__, do: Enum.sort(@__attrs__)

      @doc """
      Returns the list of relationship definitions for the compiled entity type, sorted by relationship name.
      """
      @spec __relationships__() :: list({atom, module | list(module), keyword})
      def __relationships__, do: Enum.sort(@__relationships__)
    end
  end

  @doc """
  Accumulates the given attribute definition in __attrs__ module attribute.
  """
  @spec attr(atom, atom, T.opts()) :: Macro.t()
  defmacro attr(name, type, opts \\ []) do
    quote do
      Entity.validate_attr!(__MODULE__, unquote(name), unquote(type), unquote(opts))
      Module.put_attribute(__MODULE__, :__attrs__, {unquote(name), unquote(type), unquote(opts)})
    end
  end

  @doc """
  Accumulates the given relationship definition in __relationships__ module attribute.
  A relationship is to-one when its type is a module and to-many when its type is a one-element list wrapping a module.
  """
  @spec relationship(atom, module | list(module), T.opts()) :: Macro.t()
  defmacro relationship(name, type, opts \\ []) do
    quote do
      Entity.validate_relationship!(__MODULE__, unquote(name), unquote(type), unquote(opts))

      Module.put_attribute(
        __MODULE__,
        :__relationships__,
        {unquote(name), unquote(type), unquote(opts)}
      )
    end
  end

  @doc false
  @spec register_attrs_accumulator() :: AST.t()
  def register_attrs_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__attrs__, accumulate: true)
    end
  end

  @doc false
  @spec register_relationships_accumulator() :: AST.t()
  def register_relationships_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__relationships__, accumulate: true)
    end
  end

  @doc false
  @spec validate_attr!(module, atom, any, T.opts()) :: :ok
  def validate_attr!(module, name, type, opts) do
    validate_attr_name!(module, name)
    validate_attr_type!(module, name, type)
    validate_attr_opts!(module, name, opts)
    validate_attr_values!(module, name, type, opts)
    :ok
  end

  @doc false
  @spec validate_relationship!(module, atom, any, T.opts()) :: :ok
  def validate_relationship!(module, name, _type, opts) do
    validate_relationship_name!(module, name)
    validate_relationship_opts!(module, name, opts)
    :ok
  end

  defp validate_attr_name!(module, name) do
    validate_declaration_name!(module, "attribute", name)
  end

  defp validate_attr_opts!(module, name, opts) do
    validate_known_opts!(module, "attribute", name, opts, @valid_attr_opts)
    validate_optional_opt!(module, "attribute", name, opts)
  end

  defp validate_attr_type!(module, name, type) do
    if type not in @valid_attr_types do
      valid_types = Enum.map_join(@valid_attr_types, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "invalid type #{inspect(type)} for attribute #{inspect(name)} in #{inspect(module)} - valid attribute types are: #{valid_types}"
    end
  end

  defp validate_attr_values!(module, name, :enum, opts) do
    case Keyword.fetch(opts, :values) do
      {:ok, values} ->
        validate_enum_values!(module, name, values)

      :error ->
        raise Hologram.CompileError,
          message:
            "missing values option for enum attribute #{inspect(name)} in #{inspect(module)} - enum attributes require a values option with a non-empty list of unique atoms"
    end
  end

  defp validate_attr_values!(module, name, _type, opts) do
    if Keyword.has_key?(opts, :values) do
      raise Hologram.CompileError,
        message:
          "values option not allowed for attribute #{inspect(name)} in #{inspect(module)} - the values option applies only to enum attributes"
    end
  end

  defp validate_declaration_name!(module, kind, name) do
    if name in @reserved_names do
      reserved_names = Enum.map_join(@reserved_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "reserved name #{inspect(name)} used for #{kind} in #{inspect(module)} - engine attributes #{reserved_names} are managed automatically and can't be declared"
    end

    validate_name_uniqueness!(module, kind, name)
  end

  defp validate_enum_values!(module, name, values) do
    valid =
      is_list(values) and values != [] and Enum.all?(values, &is_atom/1) and
        values == Enum.uniq(values)

    if not valid do
      raise Hologram.CompileError,
        message:
          "invalid values option #{inspect(values)} for enum attribute #{inspect(name)} in #{inspect(module)} - the values option must be a non-empty list of unique atoms"
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
      Module.get_attribute(module, :__attrs__) ++ Module.get_attribute(module, :__relationships__)

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

  defp validate_relationship_name!(module, name) do
    validate_declaration_name!(module, "relationship", name)
  end

  defp validate_relationship_opts!(module, name, opts) do
    validate_known_opts!(module, "relationship", name, opts, @valid_relationship_opts)
    validate_optional_opt!(module, "relationship", name, opts)
  end
end
