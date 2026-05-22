defmodule Hologram.Realtime do
  @moduledoc """
  Public API for Hologram's realtime layer.
  """

  alias Hologram.Component.Action
  alias Hologram.Realtime.Channel
  alias Hologram.Realtime.Receipt
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Realtime.Tombstone
  alias Hologram.Server
  alias Hologram.Server.Broadcast

  @doc """
  Broadcasts an action to subscribers of the given channel.

  Immediate counterpart to `put_broadcast`. Called from outside `Hologram.Page`
  and `Hologram.Component` handlers (`init/3`, `command/3`) - background jobs,
  GenServers, controllers, plugs, mix tasks. Fires through Phoenix.PubSub.
  Silent no-op if no connections are subscribed. Delivered to every cid that
  registered the channel via `put_subscription` on each receiving connection.
  """
  @spec broadcast_action(atom | tuple, atom, keyword | map) :: :ok
  def broadcast_action(channel, action_name, params \\ %{}) do
    Channel.validate!(channel)
    publish(channel, action_name, params, [])
  end

  @doc """
  Broadcasts an action to subscribers of the given channel, excluding the
  listed identities.

  Like `broadcast_action/3` but takes an `excluded_identities` argument first.
  Pass either a single identity tuple - `{:instance, id}`, `{:session, id}`,
  or `{:user, id}` - or a list of such tuples. Receiving SSE connections drop
  the broadcast when any of their own identities match an entry in the list.
  """
  @spec broadcast_action_except(tuple | [tuple], atom | tuple, atom, keyword | map) :: :ok
  def broadcast_action_except(excluded, channel, action_name, params \\ %{})

  def broadcast_action_except({_kind, _id} = identity, channel, action_name, params) do
    broadcast_action_except([identity], channel, action_name, params)
  end

  def broadcast_action_except(excluded_identities, channel, action_name, params)
      when is_list(excluded_identities) do
    Channel.validate!(channel)
    publish(channel, action_name, params, excluded_identities)
  end

  # Encodes a channel value to the cluster-wide PubSub topic string. Bare atoms
  # become `"hologram:channel:<atom>"`; tuples join all elements with `:` so
  # identity tuples like `{:instance, X}` round-trip through the same encoding
  # as `identity_topic/2`. Shared by `Hologram.Realtime.publish/5` and the SSE
  # process (subscribe/unsubscribe on PubSub topics).
  @doc false
  @spec channel_topic(atom | tuple) :: String.t()
  def channel_topic(channel) when is_atom(channel) do
    "hologram:channel:#{channel}"
  end

  def channel_topic(channel) when is_tuple(channel) do
    parts =
      channel
      |> Tuple.to_list()
      |> Enum.join(":")

    "hologram:channel:#{parts}"
  end

  @doc """
  Returns the PubSub topic string for an identity channel.

  `kind` must be one of `:instance`, `:session`, or `:user`.
  """
  @spec identity_topic(:instance | :session | :user, term) :: String.t()
  def identity_topic(kind, id) when kind in [:instance, :session, :user] do
    "hologram:channel:#{kind}:#{id}"
  end

  # Invoked by the framework (controller / renderer) after a handler returns
  # successfully. Iterates the LIFO list in call order, publishes each entry
  # via broadcast_action_except/5 with the originator's instance auto-added to
  # `excluded_identities` (the dev never sees this; it just prevents duplicate
  # PubSub-side delivery to the originator, who instead receives via the
  # response payload's self_echoes when subscribed). Returns the server with
  # broadcasts cleared. If the handler raises, the server state is discarded
  # before reaching here.
  @doc false
  @spec flush_broadcasts(Server.t()) :: Server.t()
  def flush_broadcasts(%Server{broadcasts: broadcasts, instance_id: instance_id} = server) do
    broadcasts
    |> Enum.reverse()
    |> Enum.each(fn %Broadcast{} = entry ->
      excluded = Enum.uniq([{:instance, instance_id} | entry.except])
      broadcast_action_except(excluded, entry.channel, entry.action_name, entry.params)
    end)

    %{server | broadcasts: []}
  end

  # Returns the list of `%Action{}`s the framework should self-echo to the
  # originator via the HTTP response payload (command POST or pageMountData).
  # An entry self-echoes iff its channel is in the originator's effective
  # subscription set (`server.subscriptions` ∪ identity channels) AND its
  # `except` list does not cover any of the originator's identities. Caller
  # must invoke this BEFORE `flush_broadcasts/1` clears the broadcasts queue.
  @doc false
  @spec get_self_echoes(Server.t()) :: [Action.t()]
  def get_self_echoes(%Server{broadcasts: broadcasts} = server) do
    own_identities = identity_channels_for(server)
    effective_channels = effective_subscriptions(server, own_identities)

    broadcasts
    |> Enum.reverse()
    |> Enum.filter(fn %Broadcast{channel: channel, except: except} ->
      MapSet.member?(effective_channels, channel) and
        not Enum.any?(except, &(&1 in own_identities))
    end)
    |> Enum.map(fn %Broadcast{} = entry ->
      # TODO: replace the placeholder target with per-binding materialization
      # (one Action per `{channel, cid}` in `server.subscriptions` matching the
      # broadcast's channel).
      %Action{name: entry.action_name, params: Map.new(entry.params), target: "page"}
    end)
  end

  @doc """
  Announces an identity change on the announce topic when the post-handler
  identity differs from the pre-handler identity.

  Compares `session_id` and `user_id` between `pre` and `post`. If either
  field differs and `pre.session_id` is not `nil`, broadcasts
  `{:identity_changed, post.session_id, post.user_id}` on
  `"hologram:announce:session:<pre.session_id>"`. Returns `:ok` either way.
  """
  @spec maybe_announce_identity_change(Server.t(), Server.t()) :: :ok
  def maybe_announce_identity_change(%Server{} = pre, %Server{} = post) do
    identity_changed? = pre.session_id != post.session_id or pre.user_id != post.user_id

    if identity_changed? and pre.session_id != nil do
      topic = session_announce_topic(pre.session_id)

      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        topic,
        {:identity_changed, post.session_id, post.user_id}
      )
    end

    :ok
  end

  # Returns the framework-private session announcement PubSub topic.
  #
  # Carries framework-internal cross-tab announcements scoped to a session
  # (`:identity_changed` today, other framework state-transition announcements
  # in the future). Every SSE process auto-subscribes to this topic at stream
  # open and reconciles it on session change. Not user-addressable - the
  # public realtime API surface never publishes here.
  @doc false
  @spec session_announce_topic(term) :: String.t()
  def session_announce_topic(session_id) do
    "hologram:announce:session:#{session_id}"
  end

  @doc """
  Subscribes the connections matching `identity` to a `{channel, cid}` binding.

  Validates the channel via `Channel.validate!/1`, resolves the identity tuple
  to live SSE processes through `SubscriptionRegistry.resolve_identity/1`, and
  for each matched connection:

    * registers the binding via `SubscriptionRegistry.apply_deltas/4` (which
      emits a `{:sub, channel}` self-message to the SSE process on a
      zero-crossing channel),

    * signs a fresh receipt under the entry's current `user_id` (so the
      authorization stamp tracks the connection's identity at issue time,
      consistent with the elevation rule), and

    * sends `{:add_sub_receipts, [{channel, cid, token}]}` to the SSE process
      for client-side merge.

  When `identity` resolves to no live connection, returns `:ok` without any
  side effect - no receipt is signed, no binding is registered, no future
  state is established. Raises `ArgumentError` on an invalid channel.
  """
  @spec subscribe(
          {:instance, String.t()} | {:session, term} | {:user, term},
          atom | tuple,
          String.t()
        ) :: :ok
  def subscribe(identity, channel, cid) when is_binary(cid) do
    Channel.validate!(channel)

    identity
    |> SubscriptionRegistry.resolve_identity()
    |> Enum.each(fn {instance_id, sse_pid} ->
      subscribe_target(instance_id, sse_pid, channel, cid)
    end)

    gossip_topic = Tombstone.gossip_topic()
    binding_key = {identity, channel, cid}
    channel_key = {identity, channel}

    Phoenix.PubSub.broadcast(Hologram.PubSub, gossip_topic, {:purge, binding_key})
    Phoenix.PubSub.broadcast(Hologram.PubSub, gossip_topic, {:purge, channel_key})

    :ok
  end

  @doc """
  Unsubscribes a `{channel, cid}` binding under `identity`.

  Raises `ArgumentError` on an invalid channel.
  """
  @spec unsubscribe(
          {:instance, String.t()} | {:session, term} | {:user, term},
          atom | tuple,
          String.t()
        ) :: :ok
  def unsubscribe({kind, id} = identity, channel, cid)
      when kind in [:instance, :session, :user] and is_binary(cid) do
    Channel.validate!(channel)

    tombstone_key = {identity, channel, cid}
    Tombstone.insert(tombstone_key, System.system_time(:millisecond))

    topic = identity_topic(kind, id)
    envelope = {:drop_sub_receipts, [{channel, cid}]}

    Phoenix.PubSub.broadcast(Hologram.PubSub, topic, envelope)

    :ok
  end

  @doc """
  Unsubscribes every cid binding under `identity` on `channel`.

  Raises `ArgumentError` on an invalid channel.
  """
  @spec unsubscribe_all(
          {:instance, String.t()} | {:session, term} | {:user, term},
          atom | tuple
        ) :: :ok
  def unsubscribe_all({kind, id} = identity, channel)
      when kind in [:instance, :session, :user] do
    Channel.validate!(channel)

    tombstone_key = {identity, channel}
    Tombstone.insert(tombstone_key, System.system_time(:millisecond))

    topic = identity_topic(kind, id)
    envelope = {:drop_channel, channel}

    Phoenix.PubSub.broadcast(Hologram.PubSub, topic, envelope)

    :ok
  end

  defp effective_subscriptions(%Server{subscriptions: subscriptions}, identity_channels) do
    subscriptions
    |> Enum.map(&elem(&1, 0))
    |> Enum.concat(identity_channels)
    |> MapSet.new()
  end

  defp identity_channels_for(%Server{} = server) do
    [{:instance, server.instance_id}]
    |> prepend_identity(:session, server.session_id)
    |> prepend_identity(:user, server.user_id)
  end

  defp prepend_identity(identities, _kind, nil), do: identities

  defp prepend_identity(identities, kind, id), do: [{kind, id} | identities]

  defp publish(channel, action_name, params, excluded_identities) do
    topic = channel_topic(channel)
    message = {:broadcast_action, channel, action_name, Map.new(params), excluded_identities}
    Phoenix.PubSub.broadcast(Hologram.PubSub, topic, message)
  end

  defp subscribe_target(instance_id, sse_pid, channel, cid) do
    case SubscriptionRegistry.identity_of(instance_id) do
      {_session_id, authorizing_user_id} ->
        SubscriptionRegistry.apply_deltas(
          instance_id,
          [{channel, cid}],
          [],
          authorizing_user_id
        )

        token = Receipt.issue(channel, cid, instance_id, authorizing_user_id)
        send(sse_pid, {:add_sub_receipts, [{channel, cid, token}]})

      nil ->
        :ok
    end
  end
end
