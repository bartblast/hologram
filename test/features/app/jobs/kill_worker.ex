defmodule HologramFeatureTests.Jobs.KillWorker do
  use Hologram.Job

  attribute :label, :string

  allow :create
  allow :read, when: actor_id == user_id()

  # Kills the worker running it, the way a crash nothing can catch would - so the run ends with no
  # outcome recorded, and the row is left running, its lock held until the worker that replaces
  # this one gives it up.
  @impl Hologram.Job
  def run(_job) do
    Process.exit(self(), :kill)

    # Never reached, since the kill ends the process at once - it is what run/1 is declared to
    # answer.
    :ok
  end
end
