# credo:disable-for-this-file Credo.Check.Readability.Specs
# A job type that declares no policies at all - server-side work, which no acting user may
# enqueue without claiming the server's own authority.
defmodule Hologram.Test.Fixtures.Job.Module2 do
  use Hologram.Job

  @impl Hologram.Job
  def run(_job), do: :ok
end
