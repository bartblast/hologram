defmodule Hologram.Commons.WorkerTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Test.Fixtures.Commons.Worker
  alias Hologram.Test.Fixtures.Commons.Worker.State

  test "worker" do
    State.run()
    Worker.run()

    Worker.enqueue(1)
    Worker.enqueue(2)
    Worker.enqueue(3)

    :timer.sleep(100)

    assert State.get() == [1, 4, 9]
  end
end
