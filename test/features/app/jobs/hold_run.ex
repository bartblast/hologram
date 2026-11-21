defmodule HologramFeatureTests.Jobs.HoldRun do
  use Hologram.Job, max_attempts: 1

  attribute :label, :string

  allow :create
  allow :read, when: actor_id == user_id()

  # Holds its run until the test lets it go, standing for a slow job - a web push waiting on a
  # remote service - so a test can see other jobs run while it's still running. Registered under
  # its label, so the test can find each run to let go of, and capped, so a test that never lets
  # it go doesn't keep a run going for good.
  @impl Hologram.Job
  def run(job) do
    :yes = :global.register_name({__MODULE__, job.label}, self())

    receive do
      :go -> :ok
    after
      30_000 -> :ok
    end
  end
end
