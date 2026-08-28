defmodule Hologram.DB.Supervisor do
  @moduledoc false

  # The database, the query cache, sync and the jobs form a restart-ordered unit. The cache reads
  # the build's dump rather than deriving anything from the mapping, but its entries still describe
  # the model the database serves, so rest_for_one restarts it whenever the database restarts and
  # nothing is left answering for a model that has gone. Sync comes after it because what its
  # evaluators hold was read through that connection, and the windows they run come from the cache
  # behind them. The jobs come last: a worker runs what has already been committed and written to
  # the log the dispatcher reads, and nothing here reads through the worker.

  use Supervisor

  alias Hologram.DB
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

  @impl Supervisor
  def init(nil) do
    children = [DB, QueryCache, Sync.Supervisor, Job.Supervisor]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
