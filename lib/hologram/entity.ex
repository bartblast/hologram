defmodule Hologram.Entity do
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.AST
  alias Hologram.Entity

  @valid_attr_types [:boolean, :date, :datetime, :enum, :float, :integer, :string]

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
    validate_attr_type!(__CALLER__.module, name, type)

    quote do
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

  defp validate_attr_type!(module, name, type) do
    if type not in @valid_attr_types do
      valid_types = Enum.map_join(@valid_attr_types, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "invalid type #{Macro.to_string(type)} for attribute #{inspect(name)} in #{inspect(module)} - valid attribute types are: #{valid_types}"
    end
  end
end
