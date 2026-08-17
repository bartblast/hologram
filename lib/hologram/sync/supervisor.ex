defmodule Hologram.Sync.Supervisor do
  @moduledoc false

  # Everything a node needs to keep its clients up to date: where results live, where evaluators
  # are found and started, the connection that hears about writes, and the dispatcher that reads
  # them. Sessions are not here - each belongs to a connection and is started by it.
  #
  # Started inside the database unit rather than beside it, so that a database restart takes sync
  # with it: what evaluators hold was read through that connection, and the windows they run come
  # from the cache that repopulates behind it.

  use Supervisor

  alias Hologram.DB.Config
  alias Hologram.Sync.Dispatcher
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.Fanout
  alias Hologram.Sync.Place
  alias Hologram.Sync.Pruner
  alias Hologram.Sync.ResultStore

  @notifications Hologram.Sync.Notifications

  @doc """
  Returns the name of the connection appends are heard on.
  """
  @spec notifications() :: atom
  def notifications, do: @notifications

  @doc """
  Starts the sync supervision unit.
  """
  @spec start_link(keyword) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Evaluator.registry()},
      ResultStore,
      Evaluators,
      Place,
      notifications_child(),
      dispatcher_child(),
      Pruner
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # The dispatcher comes after what it hands work to: it starts reading straight away, and what it
  # reads goes to evaluators found through the registry started before it. It comes after the place
  # holder for the same reason - a restart resumes from what the holder kept, which it can only
  # read from a process already up. Only the pruner's position is free: it reads nothing this tree
  # holds, and prunes nothing until an hour in.
  #
  # One_for_one is what makes the holder worth having: a dispatcher that dies is replaced beside
  # sessions that did not, and those sessions go on advancing from the rounds it sends.
  defp dispatcher_child do
    {Dispatcher, handler: &Fanout.route/2, notifications: @notifications, place: Place}
  end

  # A connection of its own, outside the pool: LISTEN belongs to one connection for as long as it
  # listens, which a pooled one cannot promise.
  defp notifications_child do
    opts = Config.connection_opts(name: @notifications)

    %{
      id: @notifications,
      start: {Postgrex.Notifications, :start_link, [opts]}
    }
  end
end
