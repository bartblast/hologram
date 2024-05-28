defmodule Hologram.Page do
  alias Hologram.Component
  alias Hologram.Page
  alias Hologram.Server

  @doc """
  Initializes component and server structs (when run on the server).
  """
  @callback init(%{atom => any}, Component.t(), Server.t()) ::
              {Component.t(), Server.t()} | Component.t() | Server.t()

  @doc """
  Returns a template in the form of an anonymous function that given variable bindings returns a DOM.
  """
  @callback template() :: (map -> list)

  defmacro __using__(_opts) do
    template_path = Component.colocated_template_path(__CALLER__.file)

    [
      quote do
        import Hologram.Component,
          only: [put_action: 2, put_action: 3, put_context: 3, put_state: 2, put_state: 3]

        import Hologram.Page, only: [layout: 1, layout: 2, param: 1, route: 1]
        import Hologram.Router.Helpers, only: [asset_path: 1, page_path: 1, page_path: 2]
        import Hologram.Template, only: [sigil_H: 2]

        alias Hologram.Component
        alias Hologram.Component.Action
        alias Hologram.Component.Command
        alias Hologram.Page

        @before_compile Component

        @external_resource unquote(template_path)

        @behaviour Page

        @doc """
        Returns true to indicate that the callee module is a page module (has "use Hologram.Page" directive).

        ## Examples

            iex> __is_hologram_page__()
            true
        """
        @spec __is_hologram_page__() :: boolean
        def __is_hologram_page__, do: true

        @impl Page
        def init(_params, component, server), do: {component, server}

        defoverridable init: 3
      end,
      Component.maybe_define_template_fun(template_path, __MODULE__),
      Component.register_props_accumulator()
    ]
  end

  @doc """
  Defines page's layout metadata functions.
  """
  @spec layout(module, keyword) :: Macro.t()
  defmacro layout(module, props \\ []) do
    quote do
      @doc """
      Returns the page's layout module.

      ## Examples

          iex> __layout_module__()
          MyLayout
      """
      @spec __layout_module__() :: module
      def __layout_module__ do
        unquote(module)
      end

      @doc """
      Returns the page's layout props.

      ## Examples

          iex> __layout_props__()
          [a: 1, b: 2]
      """
      @spec __layout_props__() :: keyword
      def __layout_props__ do
        unquote(props)
      end
    end
  end

  @doc """
  Accumulates the given param name in __props__ module attribute.
  """
  @spec param(atom) :: Macro.t()
  defmacro param(name) do
    quote do
      Module.put_attribute(__MODULE__, :__props__, {unquote(name), nil, []})
    end
  end

  @doc """
  Defines page's route metadata functions.
  """
  @spec route(String.t()) :: Macro.t()
  defmacro route(path) do
    quote do
      @doc """
      Returns the page's route.

      ## Examples

          iex> __route__()
          "/my-path"
      """
      @spec __route__() :: String.t()
      def __route__ do
        unquote(path)
      end
    end
  end
end
