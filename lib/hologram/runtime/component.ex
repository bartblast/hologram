defmodule Hologram.Component do
  use Hologram.Runtime.Templatable
  alias Hologram.Component

  defmacro __using__(_opts) do
    template_path = Templatable.colocated_template_path(__CALLER__.file)

    [
      quote do
        import Hologram.Component
        import Hologram.Template, only: [sigil_H: 2]
        import Templatable, only: [put_state: 2, put_state: 3]

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
        Initializes component client struct (when run on the client).
        """
        @spec init(%{atom => any}, Component.Client.t()) :: Component.Client.t()
        def init(_props, client), do: client

        @doc """
        Initializes component client and server structs (when run on the server).
        """
        @spec init(%{atom => any}, Component.Client.t(), Component.Server.t()) ::
                {Component.Client.t(), Component.Server.t()}
                | Component.Client.t()
                | Component.Server.t()
        def init(_props, client, server), do: {client, server}

        defoverridable init: 2, init: 3
      end,
      Templatable.maybe_define_template_fun(template_path, Component)
    ]
  end
end
