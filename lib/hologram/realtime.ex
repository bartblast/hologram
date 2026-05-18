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
