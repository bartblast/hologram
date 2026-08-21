defmodule Hologram.DB.Supervisor do
  @moduledoc false

  # The database, the query cache and sync form a restart-ordered unit: the cache's
  # entries are built from modules the database's mapping must already describe, so
  # rest_for_one restarts the cache whenever the database restarts. Sync comes last
  # for the same reason: what its evaluators hold was read through that connection,
  # and the windows they run come from the cache behind them.

  use Supervisor

  alias Hologram.DB
  alias Hologram.DB.QueryCache
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
    children = [DB, QueryCache, Sync.Supervisor]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
