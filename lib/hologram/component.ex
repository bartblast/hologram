defmodule Hologram.Component do
  alias Hologram.Commons.MapUtils
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.AST
  alias Hologram.Component
  alias Hologram.Realtime.Channel
  alias Hologram.Server
  alias Hologram.Server.Broadcast
  alias Hologram.Server.Middleware

  defstruct emitted_context: %{}, next_action: nil, next_command: nil, next_page: nil, state: %{}

  defmodule Action do
    defstruct delay: 0, name: nil, params: %{}, target: nil

    @type t :: %__MODULE__{
            delay: non_neg_integer,
            name: atom(),
            params: %{atom => any},
            target: String.t() | nil
          }
  end

  defmodule Command do
    defstruct name: nil, params: %{}, target: nil

    @type t :: %__MODULE__{name: atom(), params: %{atom => any}, target: String.t() | nil}
  end

  @type t :: %__MODULE__{
          emitted_context: %{atom => any} | %{{module, atom} => any},
          next_action: Action.t() | nil,
          next_command: Command.t() | nil,
          next_page: module | {module, keyword},
          state: %{atom => any}
        }

  @doc """
  Handles a client-side action, typically triggered by a user interaction.
  """
  @callback action(atom, %{atom => any}, Component.t()) :: Component.t()

  @doc """
  Handles a server-side command dispatched from the client.
  """
  @callback command(atom, %{atom => any}, Server.t()) :: Server.t()

  @doc """
  Initializes the component struct on the client.
  """
  @callback init(%{atom => any}, Component.t()) :: Component.t()

  @doc """
  Initializes the component and server structs on the server.
  """
  @callback init(%{atom => any}, Component.t(), Server.t()) ::
              {Component.t(), Server.t()} | Component.t() | Server.t()

  @doc """
  Returns the middleware for this component - server-side steps run before its commands.

  Returns either the (possibly transformed) server struct, or a list of step captures that are folded
  over the server.
  """
  @callback middleware(Server.t()) :: Server.t() | [Middleware.step()]

  @doc """
  Returns a template in the form of an anonymous function that given variable bindings returns a DOM.
  """
  @callback template() :: (map -> list)

  @optional_callbacks [action: 3, command: 3, init: 2]

  @doc false
  @spec __helper_imports__() :: keyword
  def __helper_imports__ do
    [
      delete_subscription: 2,
      put_action: 2,
      put_action: 3,
      put_broadcast: 3,
      put_broadcast: 4,
      put_broadcast_except: 4,
      put_broadcast_except: 5,
      put_command: 2,
      put_command: 3,
      put_context: 3,
      put_page: 2,
      put_page: 3,
      put_state: 2,
      put_state: 3,
      put_subscription: 2
    ]
  end

  defmacro __using__(_opts) do
    template_path = colocated_template_path(__CALLER__.file)

    [
      quote do
        @behaviour Component

        import Hologram.Component, only: unquote([prop: 2, prop: 3] ++ __helper_imports__())
        import Hologram.Router.Helpers, only: [asset_path: 1, page_path: 1, page_path: 2]
        import Hologram.Server, only: unquote(Hologram.Server.__helper_imports__())
        import Hologram.Template, only: [sigil_HOLO: 2]

        alias Hologram.Component
        alias Hologram.Component.Action
        alias Hologram.Component.Command

        @before_compile Component

        @external_resource unquote(template_path)

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

        @impl Component
        def middleware(server), do: server

        defoverridable init: 3, middleware: 1
      end,
      maybe_register_colocated_template_markup(template_path),
      register_props_accumulator()
    ]
  end

  defmacro __before_compile__(env) do
    template_clause = maybe_build_colocated_template_clause(env, Component)

    props_clause =
      quote do
        @doc """
        Returns the list of property definitions for the compiled component.
        """
        @spec __props__() :: list({atom, atom, keyword})
        def __props__, do: Enum.reverse(@__props__)
      end

    [template_clause, props_clause]
  end

  @doc """
  Resolves the colocated template path for the given component module given its file path.
  """
  @spec colocated_template_path(String.t()) :: String.t()
  def colocated_template_path(templatable_path) do
    Path.rootname(templatable_path) <> ".holo"
  end

  @doc """
  Removes the subscription on `channel` for the current handler's component.

  The subscription is scoped to the component whose handler is running - the
  page in a page handler, the layout in a layout handler, or the component in a
  component handler. Takes effect after the handler returns successfully; if the
  handler raises, it is discarded along with the rest of the changes.

  Idempotent: removing a channel that is not subscribed is a no-op.
  """
  # Removes the {channel, server.cid} key from server.subscriptions and records
  # it as :delete in __meta__.subscription_ops; the framework drains
  # subscription_ops after a successful handler return to drive the
  # SubscriptionRegistry. The :delete op is recorded even when the key is absent
  # so the deletion still flushes to the registry. cid comes from server.cid,
  # set by the framework at handler entry ("page" / "layout" / component cid).
  @spec delete_subscription(Server.t(), atom | tuple) :: Server.t()
  def delete_subscription(server, channel) do
    Channel.validate!(channel)

    key = {channel, server.cid}

    new_subscriptions = List.delete(server.subscriptions, key)

    new_subscription_ops = Map.put(server.__meta__.subscription_ops, key, :delete)
    new_meta = %{server.__meta__ | subscription_ops: new_subscription_ops}

    %{server | subscriptions: new_subscriptions, __meta__: new_meta}
  end

  @doc """
  Builds the template clause for colocated template if markup is registered in module attribute.
  Returns nil if no colocated template is found.
  """
  @spec maybe_build_colocated_template_clause(Macro.Env.t(), module) :: AST.t()
  def maybe_build_colocated_template_clause(env, behaviour) do
    markup = Module.get_attribute(env.module, :__colocated_template_markup__)

    if markup do
      quote do
        @impl unquote(behaviour)
        def template do
          Hologram.Template.sigil_HOLO(unquote(markup), [])
        end
      end
    end
  end

  @doc """
  Registers colocated template markup in a module attribute if the template file exists.
  Returns nil if the template file doesn't exist.
  """
  @spec maybe_register_colocated_template_markup(String.t()) :: AST.t() | nil
  def maybe_register_colocated_template_markup(template_path) do
    if File.exists?(template_path) do
      markup = File.read!(template_path)

      quote do
        @__colocated_template_markup__ unquote(markup)
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
  Next action will be executed by the client-side runtime after the specified delay (in milliseconds, defaults to 0).
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
    delay = spec[:delay] || 0

    %{struct | next_action: %Action{name: name, params: params, target: target, delay: delay}}
  end

  @doc """
  Puts the given action spec to the component or server struct's next_action field.
  Next action will be executed by the client-side runtime after the specified delay (in milliseconds, defaults to 0).
  """
  @spec put_action(Component.t() | Server.t(), atom, keyword | map) :: Component.t() | Server.t()
  def put_action(struct, name, params) do
    %{struct | next_action: %Action{name: name, params: Map.new(params)}}
  end

  @doc """
  Queues an action broadcast to subscribers of `channel`.

  Sent after the handler returns successfully; if the handler raises, it is
  discarded along with the rest of the changes. Delivered to every cid that
  subscribed to the channel via `put_subscription` on each receiving connection.
  """
  # Appended to server.broadcasts; the framework flushes the queue after a
  # successful handler return.
  @spec put_broadcast(Server.t(), atom | tuple, atom) :: Server.t()
  def put_broadcast(server, channel, action_name) when is_atom(action_name) do
    append_broadcast(server, channel, action_name, %{})
  end

  @doc """
  Queues an action broadcast to subscribers of `channel` with the given params.
  See `put_broadcast/3` for delivery semantics.
  """
  @spec put_broadcast(Server.t(), atom | tuple, atom, keyword | map) :: Server.t()
  def put_broadcast(server, channel, action_name, params) when is_atom(action_name) do
    append_broadcast(server, channel, action_name, params)
  end

  @doc """
  Queues an action broadcast that excludes one or more identities from delivery.

  Like `put_broadcast/3` but takes an `except` argument naming identities
  (`{:instance, id}`, `{:session, id}`, `{:user, id}`) that should not receive
  the broadcast. `except` accepts either a single identity tuple or a list of
  identity tuples.
  """
  @spec put_broadcast_except(
          Server.t(),
          Broadcast.identity() | [Broadcast.identity()],
          atom | tuple,
          atom
        ) :: Server.t()
  def put_broadcast_except(server, except, channel, action_name) when is_atom(action_name) do
    append_broadcast(server, channel, action_name, %{}, except)
  end

  @doc """
  Like `put_broadcast_except/4` but with explicit params.
  """
  @spec put_broadcast_except(
          Server.t(),
          Broadcast.identity() | [Broadcast.identity()],
          atom | tuple,
          atom,
          keyword | map
        ) :: Server.t()
  def put_broadcast_except(server, except, channel, action_name, params)
      when is_atom(action_name) do
    append_broadcast(server, channel, action_name, params, except)
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
  @spec put_command(Component.t(), atom, keyword | map) :: Component.t()
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
    %{component | state: MapUtils.put_nested(component.state, keys, value)}
  end

  def put_state(%{state: state} = component, key, value) do
    %{component | state: Map.put(state, key, value)}
  end

  @doc """
  Subscribes the current handler's component to `channel`.

  The subscription is scoped to the component whose handler is running - the
  page in a page handler, the layout in a layout handler, or the component in a
  component handler. Once subscribed, the component receives actions broadcast
  on the channel. Takes effect after the handler returns successfully; if the
  handler raises, it is discarded along with the rest of the changes.

  Idempotent: subscribing to the same channel twice does not duplicate it.
  """
  # Appends the {channel, server.cid} key to server.subscriptions and records it
  # as :put in __meta__.subscription_ops; the framework drains subscription_ops
  # after a successful handler return to drive the SubscriptionRegistry. cid
  # comes from server.cid, set by the framework at handler entry ("page" /
  # "layout" / component cid).
  @spec put_subscription(Server.t(), atom | tuple) :: Server.t()
  def put_subscription(server, channel) do
    Channel.validate!(channel)

    key = {channel, server.cid}

    new_subscriptions =
      if key in server.subscriptions do
        server.subscriptions
      else
        [key | server.subscriptions]
      end

    new_subscription_ops = Map.put(server.__meta__.subscription_ops, key, :put)
    new_meta = %{server.__meta__ | subscription_ops: new_subscription_ops}

    %{server | subscriptions: new_subscriptions, __meta__: new_meta}
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

  defp append_broadcast(server, channel, action_name, params, except \\ []) do
    Channel.validate!(channel)

    broadcast = %Broadcast{
      channel: channel,
      action_name: action_name,
      params: Map.new(params),
      except: normalize_except(except)
    }

    %{server | broadcasts: [broadcast | server.broadcasts]}
  end

  defp normalize_except({_kind, _id} = identity), do: [identity]

  defp normalize_except(list) when is_list(list), do: list
end
