defmodule Hologram.Realtime do
  @moduledoc """
  Public API for Hologram's realtime layer.
  """

  alias Hologram.Component.Action
  alias Hologram.Server

  @doc """
  Broadcasts an action to subscribers of the given channel.

  Immediate counterpart to `put_broadcast`. Called from outside `Hologram.Page`
  and `Hologram.Component` handlers (`init/3`, `command/3`) - background jobs,
  GenServers, controllers, plugs, mix tasks. Fires through Phoenix.PubSub.
  Silent no-op if no connections are subscribed.

  `cid` is the destination component identifier on each receiving connection
  and is always required - the inside-handler `put_broadcast` defaults it to
  the currently-executing handler's cid, but no such context exists here.

  `excluded_identities` is a list of `{:instance, id}`, `{:session, id}`,
  and/or `{:user, id}` tuples. Receiving SSE connections drop the broadcast
  when any of their own identities match an entry in this list. Defaults to
  `[]` (deliver to every subscriber).
  """
  @spec broadcast_action(tuple, String.t(), atom, keyword | map, [tuple]) :: :ok
  def broadcast_action(channel, cid, action_name, params \\ %{}, excluded_identities \\ [])

  def broadcast_action({kind, id}, cid, action_name, params, excluded_identities)
      when kind in [:instance, :session, :user] and is_binary(cid) do
    action = %Action{name: action_name, params: Map.new(params), target: cid}
    topic = "hologram:channel:#{kind}:#{id}"

    Phoenix.PubSub.broadcast(
      Hologram.PubSub,
      topic,
      {:broadcast_action, action, excluded_identities}
    )
  end

  # Invoked by the framework (controller / renderer) after a handler returns
  # successfully. Iterates the LIFO list in call order, fires each entry via
  # broadcast_action/4, and clears the list. If the handler raises, the server
  # state is discarded before reaching here.
  @doc false
  @spec flush_broadcasts(Server.t()) :: Server.t()
  def flush_broadcasts(%Server{broadcasts: broadcasts} = server) do
    broadcasts
    |> Enum.reverse()
    |> Enum.each(fn {channel, cid, action_name, params} ->
      broadcast_action(channel, cid, action_name, params)
    end)

    %{server | broadcasts: []}
  end
end
