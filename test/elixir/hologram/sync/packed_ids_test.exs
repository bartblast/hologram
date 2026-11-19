defmodule Hologram.Sync.PackedIdsTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.PackedIds

  @id_1 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e01"
  @id_2 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e02"
  @id_3 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e03"
  @id_4 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e04"
  @id_5 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e05"

  describe "delete/2" do
    test "takes the given ids out, wherever they are" do
      packed = pack([@id_1, @id_2, @id_3, @id_4, @id_5])

      assert unpack(delete(packed, [@id_5, @id_1, @id_3])) == [@id_2, @id_4]
    end

    test "passes over an id that isn't there" do
      packed = pack([@id_1, @id_3])

      assert delete(packed, [@id_2, @id_4]) == packed
    end

    test "takes an id given twice out once" do
      assert unpack(delete(pack([@id_1, @id_2]), [@id_1, @id_1])) == [@id_2]
    end

    test "leaves nothing of nothing" do
      assert delete("", [@id_1]) == ""
    end
  end

  describe "index_lefts_by_right/2 and lefts_in/2" do
    test "find the left ids of the pairs with a given right id, in order" do
      packed = pack_pairs([{@id_3, @id_1}, {@id_2, @id_4}, {@id_1, @id_1}])
      index = index_lefts_by_right(packed, [@id_1, @id_4, @id_5])

      assert lefts_in(index, @id_1) == [@id_1, @id_3]
      assert lefts_in(index, @id_4) == [@id_2]
      assert lefts_in(index, @id_5) == []
    end

    test "index only the pairs with one of the given right ids" do
      packed = pack_pairs([{@id_3, @id_1}, {@id_2, @id_4}])

      assert lefts_in(index_lefts_by_right(packed, [@id_1]), @id_4) == []
    end

    test "index nothing of no pairs" do
      assert index_lefts_by_right("", [@id_1]) == %{}
    end
  end

  describe "insert/2" do
    test "adds the given ids in order, wherever they fall" do
      packed = pack([@id_2, @id_4])

      assert unpack(insert(packed, [@id_5, @id_1, @id_3])) == [@id_1, @id_2, @id_3, @id_4, @id_5]
    end

    test "keeps an id already there once" do
      packed = pack([@id_1, @id_2])

      assert insert(packed, [@id_2, @id_1, @id_2]) == packed
    end

    test "adds a new id given twice once" do
      assert unpack(insert(pack([@id_1]), [@id_3, @id_2, @id_3])) == [@id_1, @id_2, @id_3]
    end

    test "adds to nothing" do
      assert unpack(insert("", [@id_2, @id_1])) == [@id_1, @id_2]
    end
  end

  describe "member?/2" do
    test "finds an id among the packed ones" do
      packed = pack([@id_1, @id_3, @id_5])

      assert Enum.map([@id_1, @id_3, @id_5], &member?(packed, &1)) == [true, true, true]
    end

    test "doesn't find an id that isn't there, before, between or after the others" do
      packed = pack([@id_2, @id_4])

      assert Enum.map([@id_1, @id_3, @id_5], &member?(packed, &1)) == [false, false, false]
      refute member?("", @id_1)
    end
  end

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

    test "pack an id given twice once" do
      assert unpack(pack([@id_2, @id_1, @id_2])) == [@id_1, @id_2]
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

    test "pack a pair given twice once" do
      assert unpack_pairs(pack_pairs([{@id_1, @id_2}, {@id_1, @id_2}])) == [{@id_1, @id_2}]
    end

    test "refuse a pair with something that isn't a uuid" do
      assert_raise MatchError, fn -> pack_pairs([{@id_1, "0192b1e9"}]) end
    end

    test "refuse a binary that isn't whole pairs" do
      assert_raise FunctionClauseError, fn -> unpack_pairs(<<0::size(48)-unit(8)>>) end
    end
  end

  describe "pair_member?/3" do
    test "finds a pair, and not its reverse or a neighbour" do
      packed = pack_pairs([{@id_1, @id_2}, {@id_1, @id_4}, {@id_3, @id_2}])

      assert pair_member?(packed, @id_1, @id_4)
      refute pair_member?(packed, @id_2, @id_1)
      refute pair_member?(packed, @id_1, @id_3)
      refute pair_member?("", @id_1, @id_2)
    end
  end

  describe "rights_of/2" do
    test "returns the right ids of the pairs with the given left id, in order" do
      packed = pack_pairs([{@id_1, @id_2}, {@id_3, @id_5}, {@id_3, @id_1}, {@id_4, @id_3}])

      assert rights_of(packed, @id_3) == [@id_1, @id_5]
    end

    test "returns the right ids of the last pairs, in order" do
      packed = pack_pairs([{@id_1, @id_2}, {@id_3, @id_5}, {@id_3, @id_1}])

      assert rights_of(packed, @id_3) == [@id_1, @id_5]
    end

    test "returns nothing for a left id no pair has, before, between or after the others" do
      packed = pack_pairs([{@id_2, @id_1}, {@id_4, @id_1}])

      assert Enum.map([@id_1, @id_3, @id_5], &rights_of(packed, &1)) == [[], [], []]
    end
  end

  describe "split/2" do
    test "splits the given ids into those among the set and the rest" do
      set = pack([@id_1, @id_3, @id_5])

      {inside, outside} = split(set, pack([@id_2, @id_3, @id_4, @id_5]))

      assert unpack(inside) == [@id_3, @id_5]
      assert unpack(outside) == [@id_2, @id_4]
    end

    test "splits against an empty set, and splits nothing" do
      assert split("", pack([@id_1])) == {"", pack([@id_1])}
      assert split(pack([@id_1]), "") == {"", ""}
    end
  end

  describe "a binary that isn't whole ids or pairs" do
    test "is refused by every lookup" do
      ids = <<0::size(35)-unit(8)>>
      pairs = <<0::size(48)-unit(8)>>

      assert_raise FunctionClauseError, fn -> delete(ids, [@id_1]) end
      assert_raise FunctionClauseError, fn -> insert(ids, [@id_1]) end
      assert_raise FunctionClauseError, fn -> member?(ids, @id_1) end
      assert_raise FunctionClauseError, fn -> split(ids, pack([@id_1])) end
      assert_raise FunctionClauseError, fn -> split(pack([@id_1]), ids) end
      assert_raise FunctionClauseError, fn -> index_lefts_by_right(pairs, [@id_1]) end
      assert_raise FunctionClauseError, fn -> pair_member?(pairs, @id_1, @id_2) end
      assert_raise FunctionClauseError, fn -> rights_of(pairs, @id_1) end
    end
  end
end
