defmodule Hologram.Sync.ReadEdgeTest do
  # Grouped with Hologram.Sync.DispatcherTest, which starts a read edge of its own. Both start it
  # under the module's own registered name, which is one name for the whole node - overlapping,
  # the second gets {:error, {:already_started, _pid}}. A group keeps them off each other while
  # both stay async.
  use Hologram.Test.BasicCase, async: true, group: :sync_read_edge

  import Hologram.Sync.ReadEdge

  alias Hologram.Sync.ReadEdge

  @log_id "00112233445566778899aabbccddeeff"

  defp start_read_edge! do
    start_supervised!(ReadEdge)
  end

  describe "get/1" do
    test "remembers nothing before the first round" do
      assert get(start_read_edge!()) == nil
    end
  end

  describe "put/2" do
    test "records the place the log has been read up to, in the log it is in" do
      read_edge = start_read_edge!()

      :ok = put(read_edge, {{4_216, 801, 1_700_000_000_000_000}, @log_id})

      assert get(read_edge) == {{4_216, 801, 1_700_000_000_000_000}, @log_id}
    end

    test "keeps only where reading got to last" do
      read_edge = start_read_edge!()

      :ok = put(read_edge, {{4_216, 801, 1_700_000_000_000_000}, @log_id})
      :ok = put(read_edge, {{4_217, 802, 1_700_000_000_000_001}, @log_id})

      assert get(read_edge) == {{4_217, 802, 1_700_000_000_000_001}, @log_id}
    end

    test "forgets the place once what was read is found lost" do
      read_edge = start_read_edge!()

      :ok = put(read_edge, {{4_216, 801, 1_700_000_000_000_000}, @log_id})
      :ok = put(read_edge, nil)

      assert get(read_edge) == nil
    end
  end

  describe "lose/2" do
    test "forgets the place and notes the recovery under the log id the loss was found under" do
      read_edge = start_read_edge!()

      :ok = put(read_edge, {{4_216, 801, 1_700_000_000_000_000}, @log_id})
      :ok = lose(read_edge, @log_id)

      assert get(read_edge) == nil
      assert recovery(read_edge) == {:recovering, @log_id}
    end

    test "notes a recovery with no id to move when the id had moved already" do
      read_edge = start_read_edge!()

      :ok = lose(read_edge, nil)

      assert recovery(read_edge) == {:recovering, nil}
    end
  end

  describe "recovered/1" do
    test "takes the recovery away and keeps the place put since" do
      read_edge = start_read_edge!()

      :ok = lose(read_edge, @log_id)
      :ok = put(read_edge, {{4_217, 802, 1_700_000_000_000_001}, @log_id})
      :ok = recovered(read_edge)

      assert recovery(read_edge) == nil
      assert get(read_edge) == {{4_217, 802, 1_700_000_000_000_001}, @log_id}
    end
  end

  describe "recovery/1" do
    test "has no recovery under way before the first loss" do
      assert recovery(start_read_edge!()) == nil
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
