# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Job.Module1 do
  use Hologram.Job

  allow :create
  allow :read

  @impl Hologram.Job
  def run(_job), do: :ok
end
