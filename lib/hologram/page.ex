defmodule Hologram.Page do
  alias Hologram.Commons.KernelUtils
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.AST
  alias Hologram.Component
  alias Hologram.Page
  alias Hologram.Reflection
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
          only: [
            put_action: 2,
            put_action: 3,
            put_command: 2,
            put_command: 3,
            put_context: 3,
            put_page: 2,
            put_page: 3,
            put_state: 2,
            put_state: 3
          ]

        import Hologram.JS, only: [sigil_JS: 2]
        import Hologram.Page, only: [layout: 1, layout: 2, param: 2, param: 3, route: 1]
        import Hologram.Router.Helpers, only: [asset_path: 1, page_path: 1, page_path: 2]
        import Hologram.Template, only: [sigil_HOLO: 2]

        alias Hologram.Component
        alias Hologram.Component.Action
        alias Hologram.Component.Command
        alias Hologram.Page

        @before_compile Page

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
      Page.register_params_accumulator()
    ]
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc """
      Returns the list of param definitions for the compiled page.
      """
      @spec __params__() :: list({atom, atom, keyword})
      def __params__, do: Enum.reverse(@__params__)
    end
  end

  @doc """
  Casts page params string values to types specified with param/2 macro.
  """
  @spec cast_params(module, %{atom => String.t()}) :: %{atom => any}
  def cast_params(page_module, params) do
    types =
      page_module.__params__()
      |> Enum.map(fn {name, type, _opts} -> {name, type} end)
      |> Enum.into(%{})

    params
    |> Enum.map(fn {name, value} ->
      unless types[name] do
        raise Hologram.ParamError,
          message:
            ~s/page "#{Reflection.module_name(page_module)}" doesn't expect "#{name}" param/
      end

      {name, cast_param(types[name], value, name)}
    end)
    |> Enum.into(%{})
  end

  defp cast_param(:atom, value, _name) when is_atom(value) do
    value
  end

  defp cast_param(:atom, value, name) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError ->
      message =
        ~s/can't cast param "#{name}" with value #{KernelUtils.inspect(value)} to atom, because it's not an already existing atom/

      reraise Hologram.ParamError, [message: message], __STACKTRACE__
  end

  defp cast_param(:atom, value, name) do
    raise Hologram.ParamError,
      message:
        ~s/can't cast param "#{name}" with value #{KernelUtils.inspect(value)} to atom, because it's of invalid type/
  end

  defp cast_param(:float, value, _name) when is_float(value) do
    value
  end

  defp cast_param(:float, value, name) when is_binary(value) do
    case Float.parse(value) do
      {float, _remainder} ->
        float

      :error ->
        raise Hologram.ParamError,
          message:
            ~s/can't cast param "#{name}" with value #{KernelUtils.inspect(value)} to float/
    end
  end

  defp cast_param(:float, value, name) do
    raise Hologram.ParamError,
      message:
        ~s/can't cast param "#{name}" with value #{KernelUtils.inspect(value)} to float, because it's of invalid type/
  end

  defp cast_param(:integer, value, _name) when is_integer(value) do
    value
  end

  defp cast_param(:integer, value, name) when is_binary(value) do
    case Integer.parse(value) do
      {integer, _remainder} ->
        integer

      :error ->
        raise Hologram.ParamError,
          message:
            ~s/can't cast param "#{name}" with value #{KernelUtils.inspect(value)} to integer/
    end
  end

  defp cast_param(:integer, value, name) do
    raise Hologram.ParamError,
      message:
        ~s/can't cast param "#{name}" with value #{KernelUtils.inspect(value)} to integer, because it's of invalid type/
  end

  defp cast_param(:string, value, _name) when is_binary(value) do
    value
  end

  defp cast_param(:string, value, name) do
    raise Hologram.ParamError,
      message:
        ~s/can't cast param "#{name}" with value #{KernelUtils.inspect(value)} to string, because it's of invalid type/
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
  Accumulates the given param definition in __params__ module attribute.
  """
  @spec param(atom, atom, T.opts()) :: Macro.t()
  defmacro param(name, type, opts \\ []) do
    quote do
      Module.put_attribute(__MODULE__, :__params__, {unquote(name), unquote(type), unquote(opts)})
    end
  end

  @doc """
  Returns the AST of code that registers __params__ module attribute.
  """
  @spec register_params_accumulator() :: AST.t()
  def register_params_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__params__, accumulate: true)
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
