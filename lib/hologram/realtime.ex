defmodule Hologram.Realtime do
  @moduledoc """
  Public API for Hologram's realtime layer.
  """

  alias Hologram.Component.Action
  alias Hologram.Server
  alias Hologram.Server.Broadcast

  @doc """
  Broadcasts an action to subscribers of the given channel.

  Immediate counterpart to `put_broadcast`. Called from outside `Hologram.Page`
  and `Hologram.Component` handlers (`init/3`, `command/3`) - background jobs,
  GenServers, controllers, plugs, mix tasks. Fires through Phoenix.PubSub.
  Silent no-op if no connections are subscribed.

  `cid` is the destination component identifier on each receiving connection
  and is always required - the inside-handler `put_broadcast` defaults it to
  the currently-executing handler's cid, but no such context exists here.
  """
  @spec broadcast_action(tuple, String.t(), atom, keyword | map) :: :ok
  def broadcast_action(channel, cid, action_name, params \\ %{}) do
    publish(channel, cid, action_name, params, [])
  end

  @doc """
  Broadcasts an action to subscribers of the given channel, excluding the
  listed identities.

  Like `broadcast_action/4` but takes an `excluded_identities` argument first.
  Pass either a single identity tuple - `{:instance, id}`, `{:session, id}`,
  or `{:user, id}` - or a list of such tuples. Receiving SSE connections drop
  the broadcast when any of their own identities match an entry in the list.

  `cid` is the destination component identifier on each receiving connection
  and is always required - the inside-handler `put_broadcast` defaults it to
  the currently-executing handler's cid, but no such context exists here.
  """
  @spec broadcast_action_except(tuple | [tuple], tuple, String.t(), atom, keyword | map) :: :ok
  def broadcast_action_except(excluded, channel, cid, action_name, params \\ %{})

  def broadcast_action_except({_kind, _id} = identity, channel, cid, action_name, params) do
    broadcast_action_except([identity], channel, cid, action_name, params)
  end

  def broadcast_action_except(excluded_identities, channel, cid, action_name, params)
      when is_list(excluded_identities) do
    publish(channel, cid, action_name, params, excluded_identities)
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
      broadcast_action_except(excluded, entry.channel, entry.cid, entry.action_name, entry.params)
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
      %Action{name: entry.action_name, params: Map.new(entry.params), target: entry.cid}
    end)
  end

  @doc """
  Announces an identity change on the session topic when the post-handler
  identity differs from the pre-handler identity.

  Compares `session_id` and `user_id` between `pre` and `post`. If either
  field differs and `pre.session_id` is not `nil`, broadcasts
  `{:identity_changed, post.session_id, post.user_id}` on
  `"hologram:channel:session:<pre.session_id>"`. Returns `:ok` either way.
  """
  @spec maybe_announce_identity_change(Server.t(), Server.t()) :: :ok
  def maybe_announce_identity_change(%Server{} = pre, %Server{} = post) do
    identity_changed? = pre.session_id != post.session_id or pre.user_id != post.user_id

    if identity_changed? and pre.session_id != nil do
      Phoenix.PubSub.broadcast(
        Hologram.PubSub,
        "hologram:channel:session:#{pre.session_id}",
        {:identity_changed, post.session_id, post.user_id}
      )
    end

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

  defp publish({kind, id}, cid, action_name, params, excluded_identities)
       when kind in [:instance, :session, :user] and is_binary(cid) do
    action = %Action{name: action_name, params: Map.new(params), target: cid}
    topic = "hologram:channel:#{kind}:#{id}"

    Phoenix.PubSub.broadcast(
      Hologram.PubSub,
      topic,
      {:broadcast_action, action, excluded_identities}
    )
  end
end
