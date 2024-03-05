defmodule Hologram.Runtime.Templatable do
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
end
