# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Job.Module1 do
  use Hologram.Job

  allow :create
  allow :read

  # Records that it ran, in order, so that a test can see which job a pass reached first without
  # asking a clock - two rows written in one tick of a coarse system clock carry the same
  # timestamp, and Windows ticks about every 16 ms.
  @impl Hologram.Job
  def run(job) do
    Process.put(:ran_order, [job.id | Process.get(:ran_order, [])])

    :ok
  end
end
