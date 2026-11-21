defmodule HologramSyncBenchmark.TasksPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramSyncBenchmark.Entities.Task

  route "/tasks"

  layout HologramSyncBenchmark.Components.DefaultLayout

  state :tenant_id, :string

  # The tenants case's clients greet with this page. Sync sends every task the client's user may
  # read, so the server judges each task a write touches against each client's user, and each
  # client downloads its own tenant's.
  derived :tasks, [Task], fn tenant_id -> filter(Task, tenant_id == ^tenant_id) end

  def init(_params, component, _server) do
    put_state(component, :tenant_id, nil)
  end

  def template do
    ~HOLO"""
    <p>{length(@tasks)} tasks</p>
    """
  end
end
