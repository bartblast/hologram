defmodule Hologram.Sync.GateTest do
  use Hologram.Test.BasicCase, async: false

  alias Hologram.Sync.Gate

  setup do
    put_app_env(:sync, catchups_at_once: 2)

    wait_for_process_cleanup(Gate)
    start_supervised!(Gate)

    :ok
  end

  # A process asking the gate in, which reports to the test when it is let in and leaves or ends
  # when told.
  defp asker(name) do
    test_pid = self()

    pid =
      spawn(fn ->
        Gate.ask()
        send(test_pid, {:asked, name})

        receive do
          {:gate, :open} -> send(test_pid, {:open, name})
        end

        receive do
          :leave -> Gate.leave()
        end

        Process.sleep(:infinity)
      end)

    # The ask is a cast sent before the asker reports it, so once the gate has handled what reached
    # it, one asked after another reaches the gate after it.
    assert_receive {:asked, ^name}
    :sys.get_state(Gate)

    pid
  end

  describe "ask/1" do
    test "lets in as many at once as catchups_at_once/0 answers" do
      asker(:first)
      asker(:second)
      asker(:third)

      assert_receive {:open, :first}
      assert_receive {:open, :second}
      refute_receive {:open, :third}, 100
    end

    test "lets the next one in, in the order they asked, when one leaves" do
      first = asker(:first)
      asker(:second)
      asker(:third)
      asker(:fourth)

      assert_receive {:open, :first}
      assert_receive {:open, :second}

      send(first, :leave)

      assert_receive {:open, :third}
      refute_receive {:open, :fourth}, 100
    end

    test "lets the next one in when one let in ends" do
      first = asker(:first)
      asker(:second)
      asker(:third)

      assert_receive {:open, :second}

      Process.exit(first, :kill)

      assert_receive {:open, :third}
    end

    test "passes over one that ended while it waited" do
      first = asker(:first)
      asker(:second)
      waiting = asker(:waiting)
      asker(:fourth)

      Process.exit(waiting, :kill)

      # The gate hears of the end from the runtime, so it is waited for rather than raced.
      wait_until(fn -> MapSet.size(:sys.get_state(Gate).waiting) == 1 end)

      send(first, :leave)

      assert_receive {:open, :fourth}
      refute waiting in Map.keys(:sys.get_state(Gate).holders)
    end

    test "tells the asker when the gate goes" do
      ref = Gate.ask()

      stop_supervised!(Gate)

      assert_receive {:DOWN, ^ref, :process, _gate, _reason}
    end
  end

  describe "catchups_at_once/0" do
    test "raises for anything but a positive integer" do
      put_app_env(:sync, catchups_at_once: 0)

      assert_raise ArgumentError, ~r/expects a positive integer, got: 0/, fn ->
        Gate.catchups_at_once()
      end
    end

    test "answers the configured number" do
      assert Gate.catchups_at_once() == 2
    end

    test "answers 4 when none is configured" do
      sync = Application.get_env(:hologram, :sync, [])
      Application.put_env(:hologram, :sync, Keyword.delete(sync, :catchups_at_once))

      assert Gate.catchups_at_once() == 4
    end
  end

  describe "leave/1" do
    test "passes over one the gate never let in" do
      Gate.leave()

      assert :sys.get_state(Gate).holders == %{}
    end
  end
end
