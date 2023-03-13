defmodule Hologram.Test.Fixtures.Commons.Worker do
  use Hologram.Commons.Worker
  alias Hologram.Test.Fixtures.Commons.Worker.State

  @impl true
  def perform(job) do
    State.push(job * job)
  end
end
