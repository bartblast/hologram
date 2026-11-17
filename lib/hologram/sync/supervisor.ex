defmodule Hologram.Sync.Supervisor do
  @moduledoc false

  # Everything a node needs to keep its clients up to date: where results live, where evaluators
  # are found and started, where the sync sessions on the node are listed, the connection that
  # hears about writes, and the dispatcher that reads them. The sessions themselves are not here -
  # each belongs to a connection and is started by it.
  #
  # Started inside the database unit rather than beside it, so that a database restart takes sync
  # with it: what evaluators hold was read through that connection, and the windows they run come
  # from the cache that repopulates behind it.
  #
  # A database that is away takes down nothing here. The listener waits for it rather than failing
  # (see Hologram.DB.Listener), and ends once when a session it had is lost, a LISTEN goes
  # unanswered for 4 seconds or its first statement for 150, taking the dispatcher with it. The
  # dispatcher crashes on each round it cannot read, which a pool checkout gives up on after about
  # 4 seconds with DBConnection's default queue settings: once per poll and checkout, about 9
  # seconds, when it resumes from the read edge, and once per checkout when it has nothing to
  # resume from and reads the log's edge as it starts. Either way it stays within 3 restarts in 5
  # seconds, and only it restarts.

  use Supervisor

  alias Hologram.DB.Listener
  alias Hologram.Sync.Dispatcher
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.Live
  alias Hologram.Sync.ReadEdge
  alias Hologram.Sync.ResultStore
  alias Hologram.Sync.Sessions

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
      ReadEdge,
      Sessions,
      {Listener, name: @notifications},
      dispatcher_child()
    ]

    # The order above is a dependency order, and rest_for_one is what makes it one: each child is
    # restarted with everything after it, so nothing goes on running against something that has
    # been replaced underneath it. The unit holding this one restarts the same way, for the same
    # reason.
    #
    # What it prevents is quiet rather than loud. A registry replaced on its own leaves every
    # evaluator alive and unfindable - rounds reach nobody, `Evaluator.round/3` answers `:ok` for
    # a window it cannot see, and each client sits on the last thing it was told. A notifications
    # connection replaced on its own leaves the dispatcher listening to a process that is gone,
    # which nothing reports either: it falls back to its poll and is merely slower forever.
    #
    # The session list comes after the read edge for the same reason, from the other side: a read
    # edge replaced starts the dispatcher at the log's edge as it stands, past the batches it had
    # not read yet, and a session left running would claim a place past them. Replacing the list
    # stops every session that registered in it (see `Hologram.Sync.Sessions`), so its client comes
    # back through the doors and is caught up.
    Supervisor.init(children, strategy: :rest_for_one)
  end

  # The dispatcher comes after what it hands work to: it starts reading straight away, and what it
  # reads goes to the evaluators found through the registry started before it, and to the sessions
  # listed before it. It comes after the read edge for the same reason - a restart resumes from what
  # that kept, which it can only read from a read edge that is already up.
  #
  # Being last but one is what makes keeping the edge worth it: nothing before the dispatcher is
  # restarted when the dispatcher dies, so it comes back beside the same evaluators and the same
  # sessions - which go on advancing from the rounds it sends, and would be carried past the
  # window it was reading if it resumed anywhere but where it left off.
  defp dispatcher_child do
    {Dispatcher, handler: &Live.route/2, notifications: @notifications, read_edge: ReadEdge}
  end
end
