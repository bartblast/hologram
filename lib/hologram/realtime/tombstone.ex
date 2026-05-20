defmodule Hologram.Realtime.Tombstone do
  @moduledoc false

  use GenServer

  @gossip_topic "hologram:gossip:tombstones"
  @table_name :hologram_tombstones

  @doc """
  Returns the name of the ETS table that backs the tombstone store.
  """
  @spec ets_table_name() :: atom
  def ets_table_name, do: @table_name

  @doc """
  Returns the PubSub topic used for cluster-wide gossip of tombstone inserts.
  """
  @spec gossip_topic() :: String.t()
  def gossip_topic, do: @gossip_topic

  @doc """
  Starts the tombstone store process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    Phoenix.PubSub.subscribe(Hologram.PubSub, @gossip_topic)

    {:ok, %{}}
  end
end
