defmodule Hologram.Commons.TaskUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.TaskUtils

  test "await_tasks/1" do
    res =
      1..3
      |> map_async(&(&1 + &1))
      |> await_tasks()

    assert res == [2, 4, 6]
  end

  test "map_async/2" do
    res = map_async(1..3, &(&1 + &1))

    assert [%Task{}, %Task{}, %Task{}] = res
    assert Enum.map(res, &Task.await/1) == [2, 4, 6]
  end
end
