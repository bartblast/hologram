defmodule HologramFeatureTests.Jobs.FlakyRun do
  use Hologram.Job, max_attempts: 2

  attribute :label, :string
  attribute :succeeds_on, :integer

  allow :create
  allow :read, when: actor_id == user_id()

  # Fails until the attempt it's told to succeed on, standing for a target that is down for a while.
  @impl Hologram.Job
  def run(%{attempt: attempt, succeeds_on: succeeds_on}) when attempt >= succeeds_on, do: :ok

  def run(_job), do: {:error, :target_down}
end
