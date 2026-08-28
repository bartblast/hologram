defmodule Hologram.Sync.ResultStoreTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.ResultStore

  alias Hologram.Sync.ResultStore
  alias Hologram.Test.Fixtures.Entity.Module2

  @window_id "w_7f3a"
  @other_window_id "w_c412"

  setup do
    wait_for_process_cleanup(ResultStore)
    start_supervised!(ResultStore)

    :ok
  end

  defp row(title) do
    Module2.new(a: true, c: title)
  end

  describe "fetch/2" do
    test "returns the rows a window held at the given version, keyed by id" do
      first = row("first")
      second = row("second")

      put(@window_id, 1, [first, second])

      assert %{rows: rows} = fetch(@window_id, 1)
      assert rows == %{first.id => first, second.id => second}
    end

    test "returns the ids beside the rows" do
      first = row("first")
      second = row("second")

      put(@window_id, 1, [first, second])

      assert %{ids: ids} = fetch(@window_id, 1)
      assert ids == MapSet.new([first.id, second.id])
    end

    test "returns nil for a version that was never written" do
      assert fetch(@window_id, 1) == nil
    end

    test "returns nil for a window nothing was written for" do
      put(@other_window_id, 1, [row("first")])

      assert fetch(@window_id, 1) == nil
    end

    test "returns an empty round as empty rather than as nothing" do
      put(@window_id, 1, [])

      assert fetch(@window_id, 1) == %{ids: MapSet.new(), rows: %{}}
    end
  end

  describe "forget/1" do
    test "drops every version of the given window" do
      put(@window_id, 1, [row("first")])
      put(@window_id, 2, [row("second")])

      forget(@window_id)

      assert versions(@window_id) == []
    end

    test "leaves the versions of other windows" do
      put(@window_id, 1, [row("first")])
      put(@other_window_id, 1, [row("second")])

      forget(@window_id)

      assert versions(@other_window_id) == [1]
    end
  end

  describe "put/3" do
    test "keeps the versions that fit in the ring, newest first" do
      Enum.each(1..3, fn version -> put(@window_id, version, [row("round #{version}")]) end)

      assert versions(@window_id) == [3, 2, 1]
    end

    test "drops the versions that fall out of the ring" do
      Enum.each(1..5, fn version -> put(@window_id, version, [row("round #{version}")]) end)

      assert versions(@window_id) == [5, 4, 3]
      assert fetch(@window_id, 2) == nil
    end

    test "counts the ring per window rather than across them" do
      Enum.each(1..3, fn version -> put(@window_id, version, [row("round #{version}")]) end)
      put(@other_window_id, 1, [row("other")])

      assert versions(@window_id) == [3, 2, 1]
      assert versions(@other_window_id) == [1]
    end

    # Two windows number their rounds from one apiece, so the version leaving one window's ring is
    # a version another is still holding.
    test "drops the version of the window written to, not another window's of that number" do
      Enum.each(1..2, fn version -> put(@other_window_id, version, [row("other #{version}")]) end)
      Enum.each(1..5, fn version -> put(@window_id, version, [row("round #{version}")]) end)

      assert versions(@window_id) == [5, 4, 3]
      assert versions(@other_window_id) == [2, 1]
    end
  end

  describe "ring_length/0" do
    test "keeps three versions unless told otherwise" do
      assert ring_length() == 3
    end

    test "takes the configured length" do
      put_app_env(:sync, result_ring_length: 2)

      assert ring_length() == 2

      Enum.each(1..4, fn version -> put(@window_id, version, [row("round #{version}")]) end)

      assert versions(@window_id) == [4, 3]
    end
  end

  describe "versions/1" do
    test "returns nothing for a window nothing was written for" do
      assert versions(@window_id) == []
    end
  end
end
