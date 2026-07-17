defmodule Hologram.Entity do
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.AST
  alias Hologram.Entity

  defmacro __using__(_opts) do
    [
      quote do
        import Hologram.Entity, only: [attr: 2, attr: 3]

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
      register_attrs_accumulator()
    ]
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc """
      Returns the list of attribute definitions for the compiled entity type, sorted by attribute name.
      """
      @spec __attrs__() :: list({atom, atom, keyword})
      def __attrs__, do: Enum.sort(@__attrs__)
    end
  end

  @doc """
  Accumulates the given attribute definition in __attrs__ module attribute.
  """
  @spec attr(atom, atom, T.opts()) :: Macro.t()
  defmacro attr(name, type, opts \\ []) do
    quote do
      Module.put_attribute(__MODULE__, :__attrs__, {unquote(name), unquote(type), unquote(opts)})
    end
  end

  @doc false
  @spec register_attrs_accumulator() :: AST.t()
  def register_attrs_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__attrs__, accumulate: true)
    end
  end
end
