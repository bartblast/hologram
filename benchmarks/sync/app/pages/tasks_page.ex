defmodule HologramSyncBenchmark.TasksPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramSyncBenchmark.Entities.Task

  route "/tasks"

  layout HologramSyncBenchmark.Components.DefaultLayout

  state :tenant_id, :string

  # The tenants case's clients greet with this page. The tenant comes from the page's state, which
  # the compiler can't know, so it drops the condition and the window is every tenant's tasks: the
  # server judges all of them against each client's user, one row at a time, and each client
  # downloads its own tenant's.
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
