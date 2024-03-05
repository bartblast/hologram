defmodule Hologram.Runtime.Templatable do
  alias Hologram.Compiler.AST
  alias Hologram.Component
  alias Hologram.Server

  defmacro __using__(_opts) do
    quote do
      alias Hologram.Runtime.Templatable

      @doc """
      Initializes component and server structs (when run on the server).
      """
      @callback init(%{atom => any}, Component.t(), Server.t()) ::
                  {Component.t(), Server.t()} | Component.t() | Server.t()

      @doc """
      Returns a template in the form of an anonymous function that given variable bindings returns a DOM.
      """
      @callback template() :: (map -> list)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc """
      Returns the list of property definitions for the compiled component.
      """
      @spec __props__() :: list({atom, atom, keyword})
      def __props__, do: @__props__
    end
  end

  @doc """
  Accumulates the given property definition in __props__ module attribute.
  """
  @spec prop(atom, atom, keyword) :: Macro.t()
  defmacro prop(name, type, opts \\ []) do
    quote do
      Module.put_attribute(__MODULE__, :__props__, {unquote(name), unquote(type), unquote(opts)})
    end
  end

  @doc """
  Puts the given key-value pair to the context.
  """
  @spec put_context(Component.t(), any, any) :: Component.t()
  def put_context(%{context: context} = component, key, value) do
    %{component | context: Map.put(context, key, value)}
  end

  @doc """
  Puts the given key-value entries to the component state.
  """
  @spec put_state(Component.t(), keyword | map) :: Component.t()
  def put_state(component, entries)

  def put_state(component, entries) when is_list(entries) do
    put_state(component, Enum.into(entries, %{}))
  end

  def put_state(%{state: state} = component, entries) when is_map(entries) do
    %{component | state: Map.merge(state, entries)}
  end

  @doc """
  Puts the given key-value pair to the component state.
  """
  @spec put_state(Component.t(), atom, any) :: Component.t()
  def put_state(%{state: state} = component, key, value) do
    %{component | state: Map.put(state, key, value)}
  end

  @doc """
  Returns the AST of code that registers __props__ module attribute.
  """
  @spec register_props_accumulator() :: AST.t()
  def register_props_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__props__, accumulate: true)
    end
  end
end
