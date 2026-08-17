defmodule Hologram.Sync.ReadEdge do
  @moduledoc false

  # How far this node has read the effect log - the edge it read up to, which is where the next
  # window opens - kept outside the process doing the reading.
  #
  # A dispatcher moves its edge only once a round has been handed on, so that dying halfway means
  # reading the same window again rather than passing it silently. That holds for as long as the
  # process lives and no longer: one that died and came back with nowhere to resume from would
  # start at the edge as it stands, and the rounds after it would carry every session on this node
  # past the window nobody was told about - a client left claiming to have applied what was never
  # sent, with no door back to it. Keeping the edge here is what makes a restart resume.
  #
  # Node-local and node-lifetime, deliberately. It matters only while the sessions whose own places
  # move with it are alive, and those belong to connections this node holds: a node that goes down
  # takes them with it, and the clients come back naming places of their own to be caught up from.

  use GenServer

  @doc """
  Returns how far the log has been read, or nil before the first round.
  """
  @spec get(GenServer.server()) :: non_neg_integer | nil
  def get(server) do
    GenServer.call(server, :get)
  end

  @doc """
  Records how far the log has been read.
  """
  @spec put(GenServer.server(), non_neg_integer) :: :ok
  def put(server, edge) do
    GenServer.call(server, {:put, edge})
  end

  @doc """
  Starts the holder, remembering nothing.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, nil, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl GenServer
  def init(edge) do
    {:ok, edge}
  end

  @impl GenServer
  def handle_call(:get, _from, edge) do
    {:reply, edge, edge}
  end

  # Answered rather than cast: the dispatcher reads what it wrote only after dying, so the write
  # has to have landed before the round that made it is called done.
  def handle_call({:put, edge}, _from, _previous) do
    {:reply, :ok, edge}
  end
end
