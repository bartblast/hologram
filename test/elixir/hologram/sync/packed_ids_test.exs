defmodule Hologram.Sync.PackedIdsTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.PackedIds

  @id_1 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e01"
  @id_2 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e02"
  @id_3 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e03"

  describe "pack/1 and unpack/1" do
    test "pack each id's 16 bytes in order, and read them back" do
      packed = pack([@id_3, @id_1, @id_2])

      assert byte_size(packed) == 48
      assert unpack(packed) == [@id_1, @id_2, @id_3]
    end

    test "pack nothing into an empty binary" do
      assert pack([]) == ""
      assert unpack("") == []
    end

    test "refuse something that isn't a uuid" do
      assert_raise MatchError, fn -> pack(["0192b1e9"]) end
    end

    test "refuse a binary that isn't whole ids" do
      assert_raise FunctionClauseError, fn -> unpack(<<0::size(19)-unit(8)>>) end
    end
  end

  describe "pack_pairs/1 and unpack_pairs/1" do
    test "pack each pair's 32 bytes in order, and read them back" do
      packed = pack_pairs([{@id_2, @id_1}, {@id_1, @id_3}, {@id_1, @id_2}])

      assert byte_size(packed) == 96
      assert unpack_pairs(packed) == [{@id_1, @id_2}, {@id_1, @id_3}, {@id_2, @id_1}]
    end

    test "pack no pairs into an empty binary" do
      assert pack_pairs([]) == ""
      assert unpack_pairs("") == []
    end

    test "refuse a pair with something that isn't a uuid" do
      assert_raise MatchError, fn -> pack_pairs([{@id_1, "0192b1e9"}]) end
    end

    test "refuse a binary that isn't whole pairs" do
      assert_raise FunctionClauseError, fn -> unpack_pairs(<<0::size(48)-unit(8)>>) end
    end
  end
end
