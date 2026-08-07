defmodule Hologram.Entity do
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.AST
  alias Hologram.Entity
  alias Hologram.Entity.NotIncluded
  alias Hologram.Entity.Validator

  @system_attributes [
    {:created_at, :datetime, []},
    {:id, :uuid, []},
    {:updated_at, :datetime, []}
  ]

  defmacro __using__(_opts) do
    [
      quote do
        import Hologram.Entity,
          only: [attribute: 2, attribute: 3, relationship: 2, relationship: 3]

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
      register_attributes_accumulator(),
      register_relationships_accumulator()
    ]
  end

  defmacro __before_compile__(env) do
    system_attributes =
      @system_attributes
      |> Enum.sort()
      |> Macro.escape()

    struct_fields =
      env.module
      |> struct_fields()
      |> Macro.escape()

    quote do
      defstruct unquote(struct_fields)

      @doc """
      Returns the list of attribute definitions for the compiled entity type, sorted by attribute name.
      """
      @spec __attributes__() :: list({atom, atom, keyword})
      def __attributes__, do: Enum.sort(@__attributes__)

      @doc """
      Returns the list of relationship definitions for the compiled entity type, sorted by relationship name.
      """
      @spec __relationships__() :: list({atom, module | list(module), keyword})
      def __relationships__, do: Enum.sort(@__relationships__)

      @doc """
      Returns the list of system attribute definitions present on every entity type, sorted by attribute name.
      """
      @spec __system_attributes__() :: list({atom, atom, keyword})
      def __system_attributes__, do: unquote(system_attributes)
    end
  end

  @doc """
  Accumulates the given attribute definition in __attributes__ module attribute.
  """
  @spec attribute(atom, atom, T.opts()) :: Macro.t()
  defmacro attribute(name, type, opts \\ []) do
    quote do
      name = unquote(name)
      type = unquote(type)
      opts = unquote(opts)

      Validator.validate_attribute!(__MODULE__, name, type, opts)
      Module.put_attribute(__MODULE__, :__attributes__, {name, type, opts})
    end
  end

  @doc """
  Accumulates the given relationship definition in __relationships__ module attribute.
  A relationship is to-one when its type is a module and to-many when its type is a one-element list wrapping a module.
  """
  @spec relationship(atom, module | list(module), T.opts()) :: Macro.t()
  defmacro relationship(name, type, opts \\ []) do
    quote do
      name = unquote(name)
      type = unquote(type)
      opts = unquote(opts)

      Validator.validate_relationship!(__MODULE__, name, type, opts)
      Module.put_attribute(__MODULE__, :__relationships__, {name, type, opts})
    end
  end

  @doc """
  Generates a new entity id - a UUIDv7 string built from the number of milliseconds since the Unix epoch (1970-01-01 UTC, 48 bits) followed by random bits (74 bits).
  Entity ids come only from this function, on the server and on the client alike.
  """
  @spec generate_id() :: String.t()
  def generate_id do
    unix_ms = System.system_time(:millisecond)
    <<rand_a::12, rand_b::62, _discarded::6>> = :crypto.strong_rand_bytes(10)

    uuid = <<unix_ms::48, 7::4, rand_a::12, 2::2, rand_b::62>>

    <<part_1::binary-size(8), part_2::binary-size(4), part_3::binary-size(4),
      part_4::binary-size(4), part_5::binary-size(12)>> = Base.encode16(uuid, case: :lower)

    "#{part_1}-#{part_2}-#{part_3}-#{part_4}-#{part_5}"
  end

  @doc """
  Builds a new entity struct of the given entity type from the given values (a map or a keyword list).
  The id is generated unless provided, declared attribute defaults are applied to absent attributes, and system timestamps are nil.
  To-one references are set via their `<name>_id` fields - relationship values themselves cannot be assigned at construction.
  """
  @spec new(module, %{optional(atom) => any} | keyword) :: struct
  def new(entity_type, values \\ %{}) do
    values_map = Map.new(values)

    validate_construction_values!(entity_type, values_map)

    declared_defaults =
      entity_type.__attributes__()
      |> Enum.filter(fn {_name, _type, opts} -> Keyword.has_key?(opts, :default) end)
      |> Map.new(fn {name, _type, opts} -> {name, Keyword.fetch!(opts, :default)} end)

    fields =
      declared_defaults
      |> Map.put(:id, generate_id())
      |> Map.merge(values_map)

    struct!(entity_type, fields)
  end

  @doc false
  @spec register_attributes_accumulator() :: AST.t()
  def register_attributes_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__attributes__, accumulate: true)
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
  @spec struct_fields(module) :: list({atom, any})
  def struct_fields(module) do
    system_attribute_fields =
      Enum.map(@system_attributes, fn {name, _type, _opts} -> {name, nil} end)

    attribute_fields =
      module
      |> Module.get_attribute(:__attributes__)
      |> Enum.map(fn {name, _type, _opts} -> {name, nil} end)

    relationship_fields =
      module
      |> Module.get_attribute(:__relationships__)
      |> Enum.flat_map(fn
        {name, [_target], _opts} ->
          [{name, %NotIncluded{relationship: name}}]

        {name, _target, _opts} ->
          # Compile-time atom creation - the reference field atoms are being defined here.
          # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
          [{:"#{name}_id", nil}, {name, %NotIncluded{relationship: name}}]
      end)

    Enum.sort(system_attribute_fields ++ attribute_fields ++ relationship_fields)
  end

  defp validate_construction_values!(entity_type, values_map) do
    assigned_relationship_name =
      entity_type.__relationships__()
      |> Enum.map(fn {name, _type, _opts} -> name end)
      |> Enum.find(&Map.has_key?(values_map, &1))

    if assigned_relationship_name do
      raise ArgumentError,
        message:
          "relationship #{inspect(assigned_relationship_name)} of #{inspect(entity_type)} cannot be assigned at construction - set a to-one reference via the :#{assigned_relationship_name}_id field, to-many edges via add_relationship"
    end

    :ok
  end
end
