defmodule Hologram.Sync.FinalLimitTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.FinalLimit, except: [advance: 6]

  alias Hologram.Sync.FinalLimit

  @run "run-1"

  defp entry(seq), do: %{inserted_at: ~U[2026-11-24 00:00:00Z], seq: seq, tx: seq * 10}

  # A round in the given run, over a log holding an entry at every serial unless told otherwise.
  defp advance(state, high, saves, opts \\ []) do
    run = Keyword.get(opts, :run, @run)
    last_seq = Keyword.get(opts, :last_seq, & &1)
    last_entry_through = Keyword.get(opts, :last_entry_through, &entry_through(&1, last_seq, run))
    entry_at = Keyword.get(opts, :entry_at, &{entry(&1), run})

    FinalLimit.advance(state, run, high, MapSet.new(saves), last_entry_through, entry_at)
  end

  defp entry_through(seq, last_seq, run) do
    case last_seq.(seq) do
      nil -> {nil, run}
      found -> {entry(found), run}
    end
  end

  defp nil_entry(_seq), do: nil

  describe "advance/6" do
    test "knows nothing before the first round" do
      assert limit(new()) == nil
    end

    test "reaches the highest serial when no save is running" do
      state = advance(new(), 10, [])

      assert limit(state) == 10
      refute waiting?(state)
    end

    test "reaches 0 on a log that has handed out nothing" do
      state = advance(new(), 0, [])

      assert limit(state) == 0
    end

    test "waits for the saves running when the serial was read" do
      state = advance(new(), 10, ["a"])

      assert limit(state) == nil
      assert waiting?(state)
    end

    test "reaches the serial once those saves have ended" do
      state =
        new()
        |> advance(10, ["a", "b"])
        |> advance(10, ["b"])

      assert limit(state) == nil

      finished = advance(state, 10, [])

      assert limit(finished) == 10
      refute waiting?(finished)
    end

    test "doesn't wait for a save that started after the serial was read" do
      state =
        new()
        |> advance(10, ["a"])
        |> advance(12, ["a", "b"])
        |> advance(12, ["b"])

      assert limit(state) == 10
      assert waiting?(state)
    end

    test "holds a later round for a save an earlier round is still waiting for" do
      state =
        new()
        |> advance(10, ["long"])
        |> advance(20, ["long", "short"])

      assert limit(advance(state, 20, ["long"])) == nil

      finished = advance(state, 20, [])

      assert limit(finished) == 20
      refute waiting?(finished)
    end

    test "tells a new connection's save from the one that ended on the same backend" do
      state =
        new()
        |> advance(10, ["3/41"])
        |> advance(11, ["3/42"])

      assert limit(state) == 10
    end

    test "queues no round for a serial already waiting" do
      state =
        new()
        |> advance(10, ["a"])
        |> advance(10, ["a", "b"])

      assert state.candidates == [{10, MapSet.new(["a"])}]
    end

    test "stops at the last entry the log holds at or below the serial" do
      state = advance(new(), 10, [], last_seq: fn 10 -> 7 end)

      assert limit(state) == 7
      refute waiting?(state)
    end

    test "stays put when the log holds nothing new at or below the serial" do
      state =
        new()
        |> advance(10, [], last_seq: fn 10 -> 7 end)
        |> advance(12, [], last_seq: fn 12 -> 7 end)

      assert limit(state) == 7
    end

    test "reaches 0 when the log holds no entry at or below the serial" do
      state = advance(new(), 5, [], last_seq: fn 5 -> nil end)

      assert limit(state) == 0
    end

    test "doesn't look at the log again for a serial already released" do
      state = advance(new(), 10, [], last_seq: fn 10 -> 7 end)

      assert advance(state, 10, [], last_seq: fn _seq -> flunk("read the log") end) == state
    end

    test "drops the rounds waiting when the server's run changes" do
      state = advance(new(), 35, ["a"])

      # After a crash the sequence is back at 33. A new save holds 34, and another committed 35. The
      # round from before the crash mustn't read the first save's end as its own.
      after_crash =
        advance(state, 35, ["x"],
          run: "run-2",
          last_seq: & &1,
          entry_at: fn _seq -> flunk("no limit to check") end
        )

      assert limit(after_crash) == nil
      assert after_crash.candidates == [{35, MapSet.new(["x"])}]
    end

    test "notices serials handed out again after the server's run changed" do
      state = advance(new(), 35, [], last_seq: fn 35 -> 33 end)

      assert limit(state) == 33

      moved = advance(state, 35, [], run: "run-2")

      assert limit(moved) == 35
    end

    test "keeps the limit when the run changes and its entry is still there" do
      state = advance(new(), 10, [])

      moved = advance(state, 10, ["a"], run: "run-2", entry_at: &{entry(&1), "run-2"})

      assert limit(moved) == 10
      assert waiting?(moved)
      assert losses(moved) == 0
    end

    test "goes back to no limit when the run changes and its entry is gone" do
      state = advance(new(), 10, [])

      moved = advance(state, 8, ["a"], run: "run-2", entry_at: &{nil_entry(&1), "run-2"})

      assert limit(moved) == nil
      assert moved.limit_entry == nil
      assert losses(moved) == 1
    end

    test "goes back to no limit when the run changes and another entry took the serial" do
      state = advance(new(), 10, [])

      other = %{entry(10) | tx: 999}

      moved = advance(state, 10, ["a"], run: "run-2", entry_at: fn 10 -> {other, "run-2"} end)

      assert limit(moved) == nil
      assert losses(moved) == 1
    end

    test "goes back to no limit when another entry with the same transaction took the serial" do
      state = advance(new(), 10, [])

      other = %{entry(10) | inserted_at: ~U[2026-11-24 00:00:01Z]}

      moved = advance(state, 10, ["a"], run: "run-2", entry_at: fn 10 -> {other, "run-2"} end)

      assert limit(moved) == nil
    end

    test "changes nothing when the run moves again while the limit's entry is read" do
      state = advance(new(), 10, [])

      assert advance(state, 12, [], run: "run-2", entry_at: fn _seq -> {nil, "run-3"} end) ==
               state
    end

    test "releases nothing when the log was read in another run" do
      state = advance(new(), 10, ["a"])

      waiting = advance(state, 10, [], last_entry_through: fn 10 -> {entry(10), "run-2"} end)

      assert limit(waiting) == nil
      assert waiting?(waiting)
    end

    test "never moves down within a run" do
      state =
        new()
        |> advance(10, [], last_seq: fn 10 -> 7 end)
        |> advance(12, [], last_seq: fn 12 -> 5 end)

      assert limit(state) == 7
    end

    test "keeps the waiting rounds bounded, replacing the newest" do
      state =
        Enum.reduce(1..100, new(), fn serial, acc ->
          advance(acc, serial, ["long"])
        end)

      assert length(state.candidates) == 64
      assert [{100, _holders} | _older] = state.candidates
      assert List.last(state.candidates) == {1, MapSet.new(["long"])}

      released = advance(state, 100, [])

      assert limit(released) == 100
    end
  end

  describe "holders/1" do
    test "returns no saves when no round waits" do
      assert holders(new()) == MapSet.new()
    end

    test "returns the saves the waiting rounds still wait for" do
      state =
        new()
        |> advance(10, ["a", "b"])
        |> advance(12, ["b", "c"])

      assert holders(state) == MapSet.new(["b", "c"])
    end

    test "returns no saves once the rounds are over" do
      state =
        new()
        |> advance(10, ["a"])
        |> advance(10, [])

      assert holders(state) == MapSet.new()
    end
  end

  describe "losses/1" do
    test "is none for a limit that knows of no serial yet" do
      assert losses(new()) == 0
    end
  end

  describe "run/1" do
    test "returns nothing before the first round" do
      assert run(new()) == nil
    end

    test "returns the run the last round read in" do
      state =
        new()
        |> advance(10, [])
        |> advance(11, [], run: "run-2")

      assert run(state) == "run-2"
    end
  end

  describe "place/1" do
    test "returns nothing before the first round to finish" do
      assert place(new()) == nil
      assert place(advance(new(), 10, ["a"])) == nil
    end

    test "returns the place of the entry the limit stands on" do
      state = advance(new(), 10, [])

      assert place(state) == {10, 100, DateTime.to_unix(~U[2026-11-24 00:00:00Z], :microsecond)}
    end

    test "returns the place before the first entry while the log holds none" do
      state = advance(new(), 10, [], last_entry_through: &{nil_entry(&1), @run})

      assert place(state) == {0, 0, 0}
    end
  end
end
