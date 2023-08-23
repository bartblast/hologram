defmodule Hologram.Layout do
  use Hologram.Runtime.Templatable
  alias Hologram.Layout

  defmacro __using__(_opts) do
    template_path = Templatable.colocated_template_path(__CALLER__.file)

    [
      quote do
        import Hologram.Layout
        import Templatable, only: [put_state: 3, sigil_H: 2]
        alias Hologram.Layout

        @behaviour Layout

        @external_resource unquote(template_path)

        @doc """
        Returns true to indicate that the callee module is a layout module (has "use Hologram.Layout" directive).

        ## Examples

            iex> __is_hologram_layout__()
            true
        """
        @spec __is_hologram_layout__() :: boolean
        def __is_hologram_layout__, do: true

        @doc """
        Initializes component client and server structs (when run on the server).
        """
        @spec init(%{atom => any}, Component.Client.t(), Component.Server.t()) ::
                {Component.Client.t(), Component.Server.t()}
        def init(_props, client, server), do: {client, server}

        defoverridable init: 3
      end,
      Templatable.maybe_define_template_fun(template_path, Layout)
    ]
  end
end
