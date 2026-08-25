defmodule Hologram.DB.ClockTest do
  # async: true - the clock is node-global and only ever moves forward, so there is nothing here
  # for a concurrent test to disturb.
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Clock

  describe "init/0" do
    test "keeps the counter this node already has" do
      before_init = stamp()
      init()

      assert stamp() > before_init
    end
  end

  describe "stamp/0" do
    test "returns a stamp at or above the wall clock" do
      taken_before = System.os_time(:millisecond)

      assert wall_clock_ms(stamp()) >= taken_before
    end

    test "returns strictly increasing stamps" do
      first = stamp()
      second = stamp()

      assert second > first
    end

    test "returns distinct stamps to concurrent callers" do
      stamps =
        1..10
        |> Enum.map(fn _index ->
          Task.async(fn -> Enum.map(1..100, fn _call -> stamp() end) end)
        end)
        |> Task.await_many()
        |> List.flatten()

      assert length(Enum.uniq(stamps)) == 1_000
    end
  end

  describe "wall_clock_ms/1" do
    test "reads the wall clock back from a stamp" do
      assert wall_clock_ms(1_756_100_000_123 * 1024 + 7) == 1_756_100_000_123
    end
  end
end
