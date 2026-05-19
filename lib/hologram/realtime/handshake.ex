defmodule Hologram.Realtime.Handshake do
  @moduledoc false

  use GenServer

  @gossip_topic "hologram:gossip:sse_handshakes"
  @table_name :hologram_sse_handshakes

  @doc """
  Returns the name of the ETS table that backs the handshake stash.
  """
  @spec ets_table_name() :: atom
  def ets_table_name, do: @table_name

  @doc """
  Returns the PubSub topic used for cluster-wide gossip of stash inserts.
  """
  @spec gossip_topic() :: String.t()
  def gossip_topic, do: @gossip_topic

  @doc """
  Stashes a handshake entry locally and broadcasts it on the gossip topic so
  peer nodes can mirror it into their own stash.

  `identity` is the `{instance_id, session_id, user_id}` tuple of the POSTing
  client, used at GET-time consume to verify the consumer is the same client
  that completed the POST.

  The stashed entry is `{handshake_id, validated_bindings, instance_id,
  session_id, user_id, expires_at}` (flat ETS tuple); the gossip message
  mirrors the same shape under the `:insert` tag.
  """
  @spec insert(
          String.t(),
          [{{any, String.t()}, term | nil}],
          {String.t() | nil, term | nil, term | nil},
          integer
        ) :: :ok
  def insert(handshake_id, validated_bindings, identity, expires_at) do
    GenServer.call(
      __MODULE__,
      {:insert, handshake_id, validated_bindings, identity, expires_at}
    )
  end

  @doc """
  Starts the handshake stash process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    {:ok, %{}}
  end

  @impl GenServer
  def handle_call(
        {:insert, handshake_id, validated_bindings, {instance_id, session_id, user_id},
         expires_at},
        _from,
        state
      ) do
    :ets.insert(
      @table_name,
      {handshake_id, validated_bindings, instance_id, session_id, user_id, expires_at}
    )

    Phoenix.PubSub.broadcast(
      Hologram.PubSub,
      @gossip_topic,
      {:insert, handshake_id, validated_bindings, instance_id, session_id, user_id, expires_at}
    )

    {:reply, :ok, state}
  end
end
