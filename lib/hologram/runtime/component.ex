defmodule Hologram.Component do
  alias Hologram.Template.Builder

  defmacro __using__(_opts) do
    quote do
      import Hologram.Component

      @doc """
      Returns true to indicate that the callee module is a component module (has "use Hologram.Component" directive).

      ## Examples

          iex> __is_hologram_component__()
          true
      """
      @spec __is_hologram_component__() :: boolean
      def __is_hologram_component__, do: true

      def init(_props), do: %{}

      def init(_props, _conn), do: %{}

      defoverridable init: 1, init: 2
    end
  end

  defmacro sigil_H({:<<>>, _meta, [markup]}, _modifiers) do
    quote do
      fn var!(data) ->
        _fix_unused_data_var = var!(data)
        unquote(Builder.build(markup))
      end
    end
  end
end
