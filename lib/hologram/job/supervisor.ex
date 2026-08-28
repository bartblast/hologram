defmodule Hologram.Job.Supervisor do
  @moduledoc false

  # The worker and the connection it hears writes on.
  #
  # rest_for_one, so a connection that ends takes the worker with it and the worker listens again
  # as it comes back. A worker left standing would keep waiting on a connection that is gone, which
  # nothing reports: it would fall back to its poll and simply be slower for good.

  use Supervisor

  alias Hologram.DB.Config
  alias Hologram.Job.Worker

  @notifications Hologram.Job.Notifications

  @doc """
  Returns the name of the connection writes are heard on.
  """
  @spec notifications() :: atom
  def notifications, do: @notifications

  @doc """
  Starts the job supervision unit.
  """
  @spec start_link(keyword) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    children = [
      Config.listener_child_spec(@notifications),
      {Worker, name: Worker, notifications: @notifications}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
