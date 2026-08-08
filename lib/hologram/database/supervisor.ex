defmodule Hologram.Database.Supervisor do
  @moduledoc false

  # The database and the query cache form a restart-ordered unit: a database
  # restart re-derives the plain mapping, and the cache must repopulate right
  # after it to re-enrich the mapping with the registered queries' sort-key
  # companions - rest_for_one restarts the cache whenever the database restarts.

  use Supervisor

  alias Hologram.Database
  alias Hologram.Database.QueryCache

  @doc """
  Starts the database supervision unit.
  """
  @spec start_link(keyword) :: Supervisor.on_start()
  def start_link([]) do
    Supervisor.start_link(__MODULE__, nil)
  end

  @impl Supervisor
  def init(nil) do
    children = [Database, QueryCache]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
