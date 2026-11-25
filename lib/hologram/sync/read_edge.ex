defmodule Hologram.Sync.ReadEdge do
  @moduledoc false

  # How far this node has read the oplog - the place of the entry it read up to (see
  # `Hologram.DB.Oplog.place/1`), which is where the next read starts, beside the id of the log it
  # is a place in (see `Hologram.DB.Oplog.log_id/0`) - kept outside the process doing the reading.
  #
  # A dispatcher moves its edge only once a round has been handed on, so that dying halfway means
  # reading the same effects again rather than passing them silently. That holds for as long as the
  # process lives and no longer: one that died and came back with nowhere to resume from would
  # start at the final limit as it stands, and the rounds after it would carry every session on this node
  # past the effects nobody was told about - a client left claiming to have applied what was never
  # sent, with no door back to it. Keeping the edge here is what makes a restart resume.
  #
  # Node-local and node-lifetime, deliberately. It matters only while the sessions whose own places
  # move with it are alive, and those belong to connections this node holds: a node that goes down
  # takes them with it, and the clients come back naming places of their own to be caught up from.
  #
  # Beside the edge it keeps a recovery under way: a loss found clears the edge, and the log takes a
  # new id and the sessions are stopped after. A dispatcher dying in between would come back to no
  # edge and nothing telling it the rest is owed, so it finds the recovery here and finishes it.

  use GenServer

  alias Hologram.DB.Oplog

  @typedoc """
  A place read up to, and the id of the log it is in.
  """
  @type edge :: {Oplog.place(), String.t()}

  @typedoc """
  A recovery from a loss not finished yet, with the id the log was found to have lost commits
  under, or nil when the id had moved already (see `Hologram.Sync.Dispatcher`).
  """
  @type recovery :: {:recovering, String.t() | nil}

  @doc """
  Returns how far the log has been read, or nil before the first round.
  """
  @spec get(GenServer.server()) :: edge | nil
  def get(server) do
    GenServer.call(server, :get)
  end

  @doc """
  Records how far the log has been read, or nil once what was read is found lost (see
  `Hologram.Sync.FinalLimit.losses/1`).
  """
  @spec put(GenServer.server(), edge | nil) :: :ok
  def put(server, edge) do
    GenServer.call(server, {:put, edge})
  end

  @doc """
  Forgets the place, as `put/2` with nil does, and records in the same step a recovery under way
  from the loss found under the given log id, or nil when the id had moved already.
  """
  @spec lose(GenServer.server(), String.t() | nil) :: :ok
  def lose(server, log_id) do
    GenServer.call(server, {:lose, log_id})
  end

  @doc """
  Records that the recovery under way, if any, is finished.
  """
  @spec recovered(GenServer.server()) :: :ok
  def recovered(server) do
    GenServer.call(server, :recovered)
  end

  @doc """
  Returns the recovery from a loss not finished yet, or nil.
  """
  @spec recovery(GenServer.server()) :: recovery | nil
  def recovery(server) do
    GenServer.call(server, :recovery)
  end

  @doc """
  Starts the holder, remembering nothing.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, nil, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl GenServer
  def init(nil) do
    {:ok, %{edge: nil, recovery: nil}}
  end

  @impl GenServer
  def handle_call(:get, _from, state) do
    {:reply, state.edge, state}
  end

  def handle_call(:recovery, _from, state) do
    {:reply, state.recovery, state}
  end

  # Answered rather than cast: the dispatcher reads what it wrote only after dying, so the write
  # has to have landed before the round that made it is called done.
  def handle_call({:put, edge}, _from, state) do
    {:reply, :ok, %{state | edge: edge}}
  end

  def handle_call({:lose, log_id}, _from, _state) do
    {:reply, :ok, %{edge: nil, recovery: {:recovering, log_id}}}
  end

  def handle_call(:recovered, _from, state) do
    {:reply, :ok, %{state | recovery: nil}}
  end
end
