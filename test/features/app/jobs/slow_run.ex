defmodule HologramFeatureTests.Jobs.SlowRun do
  use Hologram.Job, max_attempts: 1, timeout: 1_000

  attribute :label, :string

  allow :create
  allow :read, when: actor_id == user_id()

  # Never returns, so only its time limit ends it. The limit leaves room for the claim on a busy
  # machine, since a run killed before its claim commits isn't counted and is tried again.
  @impl Hologram.Job
  def run(_job), do: Process.sleep(:infinity)
end
