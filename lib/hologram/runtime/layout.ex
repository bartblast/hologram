defmodule Hologram.Layout do
  defmacro __using__(_opts) do
    quote do
      import Hologram.Component, only: [sigil_H: 2]

      @doc """
      Returns true to indicate that the callee module is a layout module (has "use Hologram.Layout" directive).

      ## Examples

          iex> __is_hologram_layout__()
          true
      """
      @spec __is_hologram_layout__() :: boolean
      def __is_hologram_layout__, do: true

      @doc """
      Builds the initial layout state.
      """
      @spec init(map, Conn.t()) :: map
      def init(_props, _conn), do: %{}

      defoverridable init: 2
    end
  end
end
