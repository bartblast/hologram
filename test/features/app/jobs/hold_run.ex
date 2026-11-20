defmodule HologramFeatureTests.Jobs.HoldRun do
  use Hologram.Job

  attribute :label, :string

  allow :create
  allow :read, when: actor_id == user_id()

  # Holds its run until the test lets it go, standing for a slow job - a web push waiting on a
  # remote service - so a test can see other jobs run while it's still running. Registered under
  # its module, so the test can find the run to let go of, and capped, so a test that never lets
  # it go doesn't keep a run going for good.
  @impl Hologram.Job
  def run(_job) do
    Process.register(self(), __MODULE__)

    receive do
      :go -> :ok
    after
      30_000 -> :ok
    end
  end
end
