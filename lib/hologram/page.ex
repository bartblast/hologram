defmodule Hologram.Page do
  alias Hologram.Commons.KernelUtils
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.AST
  alias Hologram.Component
  alias Hologram.Page
  alias Hologram.Reflection
  alias Hologram.Server

  @doc """
  Handles a client-side action, typically triggered by a user interaction.
  """
  @callback action(atom, map, Component.t()) :: Component.t()

  @doc """
  Handles a server-side command dispatched from the client.
  """
  @callback command(atom, map, Server.t()) :: Server.t()

  @doc """
  Initializes the component and server structs on the server.
  """
  @callback init(%{atom => any}, Component.t(), Server.t()) ::
              {Component.t(), Server.t()} | Component.t() | Server.t()

  @doc """
  Returns a template in the form of an anonymous function that given variable bindings returns a DOM.
  """
  @callback template() :: (map -> list)

  @optional_callbacks [action: 3, command: 3]

  @invalid_type_reason ", because it's of invalid type"

  defmacro __using__(_opts) do
    template_path = Component.colocated_template_path(__CALLER__.file)

    [
      quote do
        @behaviour Page

        use Hologram.Middleware.Builder

        import Hologram.Component, only: unquote(Hologram.Component.__helper_imports__())
        import Hologram.Page, only: [layout: 1, layout: 2, param: 2, param: 3, route: 1]
        import Hologram.Router.Helpers, only: [asset_path: 1, page_path: 1, page_path: 2]
        import Hologram.Server, only: unquote(Hologram.Server.__helper_imports__())
        import Hologram.Template, only: [sigil_HOLO: 2]

        alias Hologram.Component
        alias Hologram.Component.Action
        alias Hologram.Component.Command
        alias Hologram.Page

        @before_compile Page

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
        def init(_params, component, server), do: {component, server}

        defoverridable init: 3
      end,
      Component.maybe_register_colocated_template_markup(template_path),
      Page.register_params_accumulator()
    ]
  end

  defmacro __before_compile__(env) do
    template_clause = Component.maybe_build_colocated_template_clause(env, Page)

    params_clause =
      quote do
        @doc """
        Returns the list of param definitions for the compiled page.
        """
        @spec __params__() :: list({atom, atom, keyword})
        def __params__, do: Enum.reverse(@__params__)
      end

    [template_clause, params_clause]
  end

  @doc """
  Casts page params to types specified with param/2 macro.
  """
  @spec cast_params(%{(atom | String.t()) => any}, module) :: %{atom => any}
  def cast_params(params, page_module) do
    types =
      page_module.__params__()
      |> Enum.map(fn {name, type, _opts} -> {name, type} end)
      |> Enum.into(%{})

    params
    |> Enum.map(fn {name, value} ->
      name_atom = if is_atom(name), do: name, else: String.to_existing_atom(name)

      unless types[name_atom] do
        raise Hologram.ParamError,
          message:
            ~s/page "#{Reflection.module_name(page_module)}" doesn't expect "#{name_atom}" param/
      end

      {name_atom, cast_param(types[name_atom], value, name_atom, page_module)}
    end)
    |> Enum.into(%{})
  end

  defp cast_param(:atom, value, _name, _page_module) when is_atom(value) do
    value
  end

  defp cast_param(:atom, value, name, page_module) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError ->
      message =
        cast_error_msg(name, value, :atom, page_module) <>
          ", because it's not an already existing atom"

      reraise Hologram.ParamError, [message: message], __STACKTRACE__
  end

  defp cast_param(:atom, value, name, page_module) do
    raise Hologram.ParamError,
      message: cast_error_msg(name, value, :atom, page_module) <> @invalid_type_reason
  end

  defp cast_param(:float, value, _name, _page_module) when is_float(value) do
    value
  end

  defp cast_param(:float, value, name, page_module) when is_binary(value) do
    case Float.parse(value) do
      {float, _remainder} ->
        float

      :error ->
        raise Hologram.ParamError, message: cast_error_msg(name, value, :float, page_module)
    end
  end

  defp cast_param(:float, value, name, page_module) do
    raise Hologram.ParamError,
      message: cast_error_msg(name, value, :float, page_module) <> @invalid_type_reason
  end

  defp cast_param(:integer, value, _name, _page_module) when is_integer(value) do
    value
  end

  defp cast_param(:integer, value, name, page_module) when is_binary(value) do
    case Integer.parse(value) do
      {integer, _remainder} ->
        integer

      :error ->
        raise Hologram.ParamError, message: cast_error_msg(name, value, :integer, page_module)
    end
  end

  defp cast_param(:integer, value, name, page_module) do
    raise Hologram.ParamError,
      message: cast_error_msg(name, value, :integer, page_module) <> @invalid_type_reason
  end

  defp cast_param(:string, value, _name, _page_module) when is_binary(value) do
    value
  end

  defp cast_param(:string, value, name, page_module) do
    raise Hologram.ParamError,
      message: cast_error_msg(name, value, :string, page_module) <> @invalid_type_reason
  end

  # Naming the page is what makes the message actionable: the same param name can be declared on
  # any number of pages, and the value alone doesn't say which route was being served.
  defp cast_error_msg(name, value, type, page_module) do
    ~s/can't cast param "#{name}" with value #{KernelUtils.inspect(value)} to #{type} / <>
      ~s/in page "#{Reflection.module_name(page_module)}"/
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
    validate_param_opts!(opts, name, __CALLER__.module)

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

  # Params support no options yet, so every option given is rejected. When the first one lands
  # (e.g. :default, once params can be sourced from the query string), this becomes a check against
  # a list of allowed keys, the way prop/3 does it.
  #
  # Options reach the macro as AST, so only literals can be checked - which is every declaration
  # written out. An option value that isn't a literal is an expression, and says what it is only
  # once it runs, so it is passed through unchecked.
  defp validate_param_opts!(opts, name, module) when is_list(opts) and is_atom(name) do
    Enum.each(opts, &validate_param_opt_entry!(&1, name, module))
  end

  # A literal that isn't a list can't become one at runtime, so it is rejected here.
  defp validate_param_opts!(opts, name, module) when is_atom(name) do
    if Macro.quoted_literal?(opts) do
      raise Hologram.CompileError,
        message:
          ~s/the options for param "#{name}" in #{inspect(module)} must be a keyword list, got: / <>
            Macro.to_string(opts)
    end

    :ok
  end

  defp validate_param_opts!(_opts, _name, _module), do: :ok

  defp validate_param_opt_entry!({key, _value}, name, module) when is_atom(key) do
    raise Hologram.CompileError,
      message:
        ~s/params don't support options yet, got #{inspect(key)} for param "#{name}" in #{inspect(module)}/
  end

  # An entry that is a literal but not a {atom, value} pair can only be a mistake - a string key, a
  # bare atom in a list - so it is rejected rather than stored.
  defp validate_param_opt_entry!(entry, name, module) do
    if Macro.quoted_literal?(entry) do
      raise Hologram.CompileError,
        message:
          ~s/invalid option #{Macro.to_string(entry)} for param "#{name}" in #{inspect(module)}, / <>
            "options must be given as a keyword list"
    end

    :ok
  end
end
