defmodule Hologram.Sync.ResultStoreTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.ResultStore

  alias Hologram.Entity
  alias Hologram.Sync.ResultStore
  alias Hologram.Test.Fixtures.Entity.Module2

  @key {"w_7f3a", %{project_id: "pA"}}
  @other_key {"w_7f3a", %{project_id: "pB"}}

  setup do
    wait_for_process_cleanup(ResultStore)
    start_supervised!(ResultStore)

    :ok
  end

  defp row(title) do
    Entity.new(Module2, a: true, c: title)
  end

  describe "fetch/2" do
    test "returns the rows a window held at the given version, keyed by id" do
      first = row("first")
      second = row("second")

      put(@key, 1, [first, second])

      assert %{rows: rows} = fetch(@key, 1)
      assert rows == %{first.id => first, second.id => second}
    end

    test "returns the ids beside the rows" do
      first = row("first")
      second = row("second")

      put(@key, 1, [first, second])

      assert %{ids: ids} = fetch(@key, 1)
      assert ids == MapSet.new([first.id, second.id])
    end

    test "returns nil for a version that was never written" do
      assert fetch(@key, 1) == nil
    end

    test "returns nil for a window nothing was written for" do
      put(@other_key, 1, [row("first")])

      assert fetch(@key, 1) == nil
    end

    test "returns an empty round as empty rather than as nothing" do
      put(@key, 1, [])

      assert fetch(@key, 1) == %{ids: MapSet.new(), rows: %{}}
    end
  end

  describe "forget/1" do
    test "drops every version of the given window" do
      put(@key, 1, [row("first")])
      put(@key, 2, [row("second")])

      forget(@key)

      assert versions(@key) == []
    end

    test "leaves the versions of other windows" do
      put(@key, 1, [row("first")])
      put(@other_key, 1, [row("second")])

      forget(@key)

      assert versions(@other_key) == [1]
    end
  end

  describe "put/3" do
    test "keeps the versions that fit in the ring, newest first" do
      Enum.each(1..3, fn version -> put(@key, version, [row("round #{version}")]) end)

      assert versions(@key) == [3, 2, 1]
    end

    test "drops the versions that fall out of the ring" do
      Enum.each(1..5, fn version -> put(@key, version, [row("round #{version}")]) end)

      assert versions(@key) == [5, 4, 3]
      assert fetch(@key, 2) == nil
    end

    test "counts the ring per window rather than across them" do
      Enum.each(1..3, fn version -> put(@key, version, [row("round #{version}")]) end)
      put(@other_key, 1, [row("other")])

      assert versions(@key) == [3, 2, 1]
      assert versions(@other_key) == [1]
    end
  end

  describe "ring_length/0" do
    test "keeps three versions unless told otherwise" do
      assert ring_length() == 3
    end

    test "takes the configured length" do
      Application.put_env(:hologram, :sync, result_ring_length: 2)
      on_exit(fn -> Application.delete_env(:hologram, :sync) end)

      assert ring_length() == 2

      Enum.each(1..4, fn version -> put(@key, version, [row("round #{version}")]) end)

      assert versions(@key) == [4, 3]
    end
  end

  describe "versions/1" do
    test "returns nothing for a window nothing was written for" do
      assert versions(@key) == []
    end
  end
end
