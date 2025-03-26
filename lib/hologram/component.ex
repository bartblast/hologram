defmodule Hologram.Component do
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.AST
  alias Hologram.Component
  alias Hologram.Server

  defstruct emitted_context: %{}, next_action: nil, next_command: nil, next_page: nil, state: %{}

  defmodule Action do
    defstruct name: nil, params: %{}, target: nil

    @type t :: %__MODULE__{name: :atom, params: %{atom => any}, target: String.t() | nil}
  end

  defmodule Command do
    defstruct name: nil, params: %{}, target: nil

    @type t :: %__MODULE__{name: :atom, params: %{atom => any}, target: String.t() | nil}
  end

  @type t :: %__MODULE__{
          emitted_context: %{atom => any} | %{{module, atom} => any},
          next_action: Action.t() | nil,
          next_command: Command.t() | nil,
          next_page: module | {module, keyword},
          state: %{atom => any}
        }

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
    template_path = colocated_template_path(__CALLER__.file)

    [
      quote do
        import Hologram.Component,
          only: [
            prop: 2,
            prop: 3,
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
        import Hologram.Router.Helpers, only: [asset_path: 1, page_path: 1, page_path: 2]
        import Hologram.Template, only: [sigil_HOLO: 2]

        alias Hologram.Component
        alias Hologram.Component.Action
        alias Hologram.Component.Command

        @before_compile Component

        @external_resource unquote(template_path)

        @behaviour Component

        @doc """
        Returns true to indicate that the callee module is a component module (has "use Hologram.Component" directive).

        ## Examples

            iex> __is_hologram_component__()
            true
        """
        @spec __is_hologram_component__() :: boolean
        def __is_hologram_component__, do: true

        @impl Component
        def init(_props, component, server), do: {component, server}

        defoverridable init: 3
      end,
      maybe_define_template_fun(template_path, __MODULE__),
      register_props_accumulator()
    ]
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc """
      Returns the list of property definitions for the compiled component.
      """
      @spec __props__() :: list({atom, atom, keyword})
      def __props__, do: Enum.reverse(@__props__)
    end
  end

  @doc """
  Resolves the colocated template path for the given component module given its file path.
  """
  @spec colocated_template_path(String.t()) :: String.t()
  def colocated_template_path(templatable_path) do
    Path.rootname(templatable_path) <> ".holo"
  end

  @doc """
  Returns the AST of template/0 function definition that uses markup fetched from the give template file.
  If the given template file doesn't exist nil is returned.
  """
  @spec maybe_define_template_fun(String.t(), module) :: AST.t() | nil
  def maybe_define_template_fun(template_path, behaviour) do
    if File.exists?(template_path) do
      markup = File.read!(template_path)

      quote do
        @impl unquote(behaviour)
        def template do
          sigil_HOLO(unquote(markup), [])
        end
      end
    end
  end

  @doc """
  Accumulates the given property definition in __props__ module attribute.
  """
  @spec prop(atom, atom, T.opts()) :: Macro.t()
  defmacro prop(name, type, opts \\ []) do
    quote do
      Module.put_attribute(__MODULE__, :__props__, {unquote(name), unquote(type), unquote(opts)})
    end
  end

  @doc """
  Puts the given action spec to the component or server struct's next_action field.
  Next action will be executed by the runtime synchronously.
  """
  @spec put_action(Component.t() | Server.t(), atom | keyword) :: Component.t() | Server.t()
  def put_action(struct, name_or_spec)

  def put_action(struct, name) when is_atom(name) do
    %{struct | next_action: %Action{name: name}}
  end

  def put_action(struct, spec) when is_list(spec) do
    name = spec[:name]
    params = Map.new(spec[:params] || [])
    target = spec[:target]

    %{struct | next_action: %Action{name: name, params: params, target: target}}
  end

  @doc """
  Puts the given action spec to the component or server struct's next_action field.
  Next action will be executed by the runtime synchronously.
  """
  @spec put_action(Component.t() | Server.t(), atom, keyword) :: Component.t() | Server.t()
  def put_action(struct, name, params) do
    %{struct | next_action: %Action{name: name, params: Map.new(params)}}
  end

  @doc """
  Puts the given command spec to the component's next_command field.
  Next command will be sent asynchronously to the server.
  """
  @spec put_command(Component.t(), atom | keyword) :: Component.t()
  def put_command(component, name_or_spec)

  def put_command(%Component{} = component, name) when is_atom(name) do
    %{component | next_command: %Command{name: name}}
  end

  def put_command(%Component{} = component, spec) when is_list(spec) do
    name = spec[:name]
    params = Map.new(spec[:params] || [])
    target = spec[:target]

    %{component | next_command: %Command{name: name, params: params, target: target}}
  end

  @doc """
  Puts the given command spec to the component's next_command field.
  Next command will be sent asynchronously to the server.
  """
  @spec put_command(Component.t(), atom, keyword) :: Component.t()
  def put_command(%Component{} = component, name, params) do
    %{component | next_command: %Command{name: name, params: Map.new(params)}}
  end

  @doc """
  Puts the given key-value pair to the component's emitted_context field.
  Context emitted by a component is available to all of its child nodes.
  """
  @spec put_context(Component.t(), any, any) :: Component.t()
  def put_context(%{emitted_context: context} = component, key, value) do
    %{component | emitted_context: Map.put(context, key, value)}
  end

  @doc """
  Puts the given page module to the component's next_page field.
  The client will navigate to this page asynchronously after the current action finished executing.
  """
  @spec put_page(Component.t(), module) :: Component.t()
  def put_page(component, page_module) do
    %{component | next_page: page_module}
  end

  @doc """
  Puts the given page module and params to the component's next_page field (as a tuple).
  The client will navigate to this page asynchronously after the current action finished executing.
  """
  @spec put_page(Component.t(), module, keyword) :: Component.t()
  def put_page(component, page_module, params) do
    %{component | next_page: {page_module, params}}
  end

  @doc """
  Puts the given key-value entries to the component state.
  """
  @spec put_state(Component.t(), keyword | map) :: Component.t()
  def put_state(component, entries)

  def put_state(component, entries) when is_list(entries) do
    put_state(component, Enum.into(entries, %{}))
  end

  def put_state(%{state: state} = component, entries) when is_map(entries) do
    %{component | state: Map.merge(state, entries)}
  end

  @doc """
  If the second arg is a list of keys representing a component state path
  it puts the value in the nested component state path,
  otherwise it puts the given key-value pair to the component state.
  """
  @spec put_state(Component.t(), atom | list(atom), any) :: Component.t()

  def put_state(component, keys, value) when is_list(keys) do
    %{component | state: put_in(component.state, keys, value)}
  end

  def put_state(%{state: state} = component, key, value) do
    %{component | state: Map.put(state, key, value)}
  end

  @doc """
  Returns the AST of code that registers __props__ module attribute.
  """
  @spec register_props_accumulator() :: AST.t()
  def register_props_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__props__, accumulate: true)
    end
  end
end
