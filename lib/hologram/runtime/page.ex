defmodule Hologram.Page do
  use Hologram.Runtime.Templatable

  alias Hologram.Component
  alias Hologram.Page

  defmacro __using__(_opts) do
    template_path = Templatable.colocated_template_path(__CALLER__.file)

    [
      quote do
        import Hologram.Page
        import Templatable, only: [put_state: 3, sigil_H: 2]
        alias Hologram.Page

        @behaviour Page

        @external_resource unquote(template_path)

        @doc """
        Returns true to indicate that the callee module is a page module (has "use Hologram.Page" directive).

        ## Examples

            iex> __is_hologram_page__()
            true
        """
        @spec __is_hologram_page__() :: boolean
        def __is_hologram_page__, do: true

        @doc """
        Initializes component client and server structs (when run on the server).
        """
        @spec init(%{atom => any}, Component.Client.t(), Component.Server.t()) ::
                {Component.Client.t(), Component.Server.t()}
        def init(_params, client, server), do: {client, server}

        defoverridable init: 3
      end,
      Templatable.maybe_define_template_fun(template_path, Page)
    ]
  end

  @doc """
  Defines __hologram_layout_module__/0 which returns the page's layout module,
  and __hologram_layout_props__/0 which returns the page's layout props.

  ## Examples

      iex> __hologram_layout_module__()
      MyLayout

      iex> __hologram_layout_props__()
      [a: 1, b: 2]
  """
  @spec layout(module, keyword) :: Macro.t()
  defmacro layout(module, props \\ []) do
    quote do
      @spec __hologram_layout_module__() :: module
      def __hologram_layout_module__ do
        unquote(module)
      end

      @spec __hologram_layout_props__() :: keyword
      def __hologram_layout_props__ do
        unquote(props)
      end
    end
  end

  @doc """
  Defines __hologram_route__/0 which returns the page's route.

  ## Examples

      iex> __hologram_route__()
      "/my_path"
  """
  @spec route(String.t()) :: Macro.t()
  defmacro route(path) do
    quote do
      @spec __hologram_route__() :: String.t()
      def __hologram_route__ do
        unquote(path)
      end
    end
  end
end
