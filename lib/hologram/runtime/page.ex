defmodule Hologram.Page do
  use Hologram.Runtime.Templatable
  alias Hologram.Page

  defmacro __using__(_opts) do
    template_path = Templatable.colocated_template_path(__CALLER__.file)

    [
      quote do
        import Hologram.Page
        import Hologram.Template, only: [sigil_H: 2]
        import Templatable, only: [put_state: 2, put_state: 3]

        alias Hologram.Page

        @before_compile Templatable

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

        @impl Page
        def init(_params, client, server), do: {client, server}

        defoverridable init: 3
      end,
      Templatable.maybe_define_template_fun(template_path, Page),
      Templatable.register_props_accumulator()
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

          iex> __hologram_layout_module__()
          MyLayout
      """
      @spec __hologram_layout_module__() :: module
      def __hologram_layout_module__ do
        unquote(module)
      end

      @doc """
      Returns the page's layout props.

      ## Examples

          iex> __hologram_layout_props__()
          [a: 1, b: 2]
      """
      @spec __hologram_layout_props__() :: keyword
      def __hologram_layout_props__ do
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
      Module.put_attribute(__MODULE__, :__props__, unquote(name))
    end
  end

  @doc """
  Defines page's route metadata functions
  """
  @spec route(String.t()) :: Macro.t()
  defmacro route(path) do
    quote do
      @doc """
      Returns the page's route.

      ## Examples

          iex> __hologram_route__()
          "/my_path"
      """
      @spec __hologram_route__() :: String.t()
      def __hologram_route__ do
        unquote(path)
      end
    end
  end
end
