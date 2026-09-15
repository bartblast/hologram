defmodule Hologram.Commons.TaskUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.TaskUtils

  test "async_many/2" do
    res = async_many(1..3, &(&1 + &1))

    assert [%Task{}, %Task{}, %Task{}] = res
    assert Enum.map(res, &Task.await/1) == [2, 4, 6]
  end

  describe "map_concurrently/3" do
    test "returns results in the enumerable's order" do
      assert map_concurrently(1..5, &(&1 * 10)) == [10, 20, 30, 40, 50]
    end

    test "runs at most max_concurrency tasks at once" do
      counter = :counters.new(2, [:atomics])

      map_concurrently(
        1..20,
        fn _elem ->
          # Slot 1 counts the tasks running now; slot 2 keeps the highest count seen. The peak
          # read is not atomic with the increment, so it can under-count but never over-count.
          :counters.add(counter, 1, 1)
          running = :counters.get(counter, 1)
          if running > :counters.get(counter, 2), do: :counters.put(counter, 2, running)
          Process.sleep(10)
          :counters.sub(counter, 1, 1)
        end,
        max_concurrency: 3
      )

      assert :counters.get(counter, 2) <= 3
      assert :counters.get(counter, 2) > 1
    end

    test "a task's raise takes the caller down" do
      # The caller is linked to its tasks, so the raise reaches it as an exit, not as a raise.
      {pid, ref} = spawn_monitor(fn -> map_concurrently([1], fn _elem -> raise "boom" end) end)

      assert_receive {:DOWN, ^ref, :process, ^pid, {%RuntimeError{message: "boom"}, _stacktrace}}
    end
  end
end
