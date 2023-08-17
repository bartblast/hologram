defmodule Hologram.Component do
  use Hologram.Runtime.Templatable

  alias Hologram.Component
  alias Hologram.Conn

  defmacro __using__(_opts) do
    template_path = Templatable.colocated_template_path(__CALLER__.file)

    [
      quote do
        import Hologram.Component
        import Hologram.Runtime.Macros, only: [sigil_H: 2]
        alias Hologram.Component

        @behaviour Component

        @external_resource unquote(template_path)

        @doc """
        Returns true to indicate that the callee module is a component module (has "use Hologram.Component" directive).

        ## Examples

            iex> __is_hologram_component__()
            true
        """
        @spec __is_hologram_component__() :: boolean
        def __is_hologram_component__, do: true

        @doc """
        Builds the initial component state when run on the client.
        """
        @spec init(map) :: map
        def init(_props), do: %{}

        @doc """
        Builds the initial component state when run on the server.
        """
        @spec init(map, Conn.t()) :: map
        def init(_props, _conn), do: %{}

        defoverridable init: 1, init: 2
      end,
      Templatable.maybe_define_template_fun(template_path, Component)
    ]
  end
end
