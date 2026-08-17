defmodule Hologram.Sync.ReadEdgeTest do
  # Grouped with Hologram.Sync.DispatcherTest, which starts a read edge of its own. Both start it
  # under the module's own registered name, which is one name for the whole node - overlapping,
  # the second gets {:error, {:already_started, _pid}}. A group keeps them off each other while
  # both stay async.
  use Hologram.Test.BasicCase, async: true, group: :sync_read_edge

  import Hologram.Sync.ReadEdge

  alias Hologram.Sync.ReadEdge

  defp start_read_edge! do
    start_supervised!(ReadEdge)
  end

  describe "get/1" do
    test "remembers nothing before the first round" do
      assert get(start_read_edge!()) == nil
    end
  end

  describe "put/2" do
    test "records how far the log has been read" do
      read_edge = start_read_edge!()

      :ok = put(read_edge, 4_216)

      assert get(read_edge) == 4_216
    end

    test "keeps only where reading got to last" do
      read_edge = start_read_edge!()

      :ok = put(read_edge, 4_216)
      :ok = put(read_edge, 4_217)

      assert get(read_edge) == 4_217
    end
  end

  # The name a dispatcher is handed to resume from is the module's own, so registering under it is
  # what makes the holder findable rather than a convenience.
  describe "start_link/1" do
    test "answers to the module's own name" do
      read_edge = start_read_edge!()

      assert Process.whereis(ReadEdge) == read_edge
    end
  end
end
