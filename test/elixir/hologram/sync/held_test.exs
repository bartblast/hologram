defmodule Hologram.Sync.HeldTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Held

  alias Hologram.Sync.PackedIds
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2

  @id_1 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e01"
  @id_2 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e02"
  @id_3 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e03"

  describe "add/3" do
    test "holds the given ids of the given type" do
      held = add(new(), Module1, [@id_2, @id_1])

      assert ids(held, Module1) == [@id_1, @id_2]
      assert ids(held, Module2) == []
    end

    test "keeps the ids already held" do
      held =
        new()
        |> add(Module1, [@id_1, @id_2])
        |> add(Module1, [@id_3, @id_2])

      assert ids(held, Module1) == [@id_1, @id_2, @id_3]
    end

    test "adds nothing for no ids" do
      assert add(new(), Module1, []) == new()
    end
  end

  describe "member?/3" do
    test "answers per type" do
      held = add(new(), Module1, [@id_1])

      assert member?(held, Module1, @id_1)
      refute member?(held, Module1, @id_2)
      refute member?(held, Module2, @id_1)
    end
  end

  describe "remove/3" do
    test "takes the given ids out" do
      held =
        new()
        |> add(Module1, [@id_1, @id_2, @id_3])
        |> remove(Module1, [@id_2])

      assert ids(held, Module1) == [@id_1, @id_3]
    end

    test "leaves a type with no ids out" do
      held =
        new()
        |> add(Module1, [@id_1])
        |> remove(Module1, [@id_1])

      assert held == new()
    end

    test "passes over ids of a type held none of" do
      assert remove(new(), Module1, [@id_1]) == new()
    end
  end

  describe "split/3" do
    test "splits the given packed ids of a type into the held ones and the rest" do
      held = add(new(), Module1, [@id_1, @id_3])

      {held_ids, other_ids} = split(held, Module1, PackedIds.pack([@id_1, @id_2, @id_3]))

      assert PackedIds.unpack(held_ids) == [@id_1, @id_3]
      assert PackedIds.unpack(other_ids) == [@id_2]
    end

    test "holds none of a type it holds nothing of" do
      packed = PackedIds.pack([@id_1])

      assert split(add(new(), Module1, [@id_1]), Module2, packed) == {"", packed}
    end
  end
end
