defmodule Hologram.DB.Supervisor do
  @moduledoc false

  # The spawn mark goes first: it owns the trace session that tells work a request moved to another
  # process from server code, and everything after it reads or writes on one side of that line.
  #
  # The database, the query cache, sync and the jobs form a restart-ordered unit. The cache reads
  # the build's dump rather than deriving anything from the mapping, but what it holds still
  # describes the model the database serves, so rest_for_one restarts it whenever the database restarts and
  # nothing is left answering for a model that has gone. Sync comes after it because what its
  # sessions read goes through that connection, and the synced types they read come from the cache
  # behind them. The jobs come last: a worker runs what has already been committed and written to
  # the log the dispatcher reads, and nothing here reads through the worker. On a database
  # migrations manage, the index builder starts after all of them: the node serves while it builds
  # the indexes the queries need, and it stops once they stand (see Hologram.DB.IndexBuilder).

  use Supervisor

  alias Hologram.Auth.SpawnMark
  alias Hologram.DB
  alias Hologram.DB.EctoGuard
  alias Hologram.DB.IndexBuilder
  alias Hologram.DB.QueryCache
  alias Hologram.Job
  alias Hologram.Sync

  @doc """
  Starts the database supervision unit.
  """
  @spec start_link(keyword) :: Supervisor.on_start()
  def start_link([]) do
    Supervisor.start_link(__MODULE__, nil)
  end

  @doc """
  Returns the children of the database unit in the given env, in start order. The index builder
  is among them only where migrations manage the database: dev reconciles the plan's indexes with
  the rest of the schema at boot, and test manages its schema from the test helpers.
  """
  @spec children(atom) :: list(Supervisor.child_spec() | module | {module, any})
  def children(env) when env in [:dev, :test],
    do: [SpawnMark, DB, QueryCache, Sync.Supervisor, Job.Supervisor]

  def children(_env),
    do: [SpawnMark, DB, QueryCache, Sync.Supervisor, Job.Supervisor, {IndexBuilder, []}]

  @impl Supervisor
  def init(nil) do
    # Only an app with a data model gets here, and only its transactions have anything to protect.
    EctoGuard.attach()

    Hologram.env()
    |> children()
    |> Supervisor.init(strategy: :rest_for_one)
  end
end
