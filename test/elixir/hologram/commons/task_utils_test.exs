defmodule Hologram.Commons.TaskUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.TaskUtils

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

    test "a task's raise is raised in the caller" do
      assert_raise RuntimeError, "boom", fn ->
        map_concurrently([1, 2], fn
          1 -> :ok
          2 -> raise "boom"
        end)
      end
    end

    test "a task's raise keeps the task's stacktrace" do
      stacktrace =
        try do
          map_concurrently([1], fn _elem -> raise "boom" end)
        rescue
          RuntimeError -> __STACKTRACE__
        end

      assert Enum.any?(stacktrace, fn {module, _function, _arity, _location} ->
               module == __MODULE__
             end)
    end

    test "a task's throw is thrown in the caller" do
      assert catch_throw(map_concurrently([1], fn _elem -> throw(:boom) end)) == :boom
    end

    test "a task's exit is an exit in the caller" do
      assert catch_exit(map_concurrently([1], fn _elem -> exit(:boom) end)) == :boom
    end

    test "the caller's after clause runs when a task fails" do
      test_pid = self()

      try do
        map_concurrently([1], fn _elem -> raise "boom" end)
      rescue
        RuntimeError -> :ok
      after
        send(test_pid, :after_ran)
      end

      assert_received :after_ran
    end

    test "the tasks after a failure are not all run" do
      counter = :counters.new(1, [:atomics])

      assert_raise RuntimeError, fn ->
        map_concurrently(
          1..20,
          fn
            1 ->
              raise "boom"

            _elem ->
              :counters.add(counter, 1, 1)
              Process.sleep(50)
          end,
          max_concurrency: 2
        )
      end

      assert :counters.get(counter, 1) < 19
    end
  end
end
