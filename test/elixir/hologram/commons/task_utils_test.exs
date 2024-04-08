defmodule Hologram.Commons.TaskUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.TaskUtils

  test "map_async/2" do
    res = map_async(1..3, &(&1 + &1))

    assert [%Task{}, %Task{}, %Task{}] = res
    assert Enum.map(res, &Task.await/1) == [2, 4, 6]
  end
end
