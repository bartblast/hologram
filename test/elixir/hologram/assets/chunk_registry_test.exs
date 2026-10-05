defmodule Hologram.Assets.ChunkRegistryTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Assets.ChunkRegistry
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.ChunkRegistry
  alias Hologram.Commons.ETS

  use_module_stub :chunk_registry

  @items %{
    {:page, :module_a} => ["AAAAAAAA", "CCCCCCCC"],
    {:page, :module_b} => [],
    {:type, Date} => ["BBBBBBBB", "CCCCCCCC"],
    {:type, Time} => ["AAAAAAAA", "CCCCCCCC"]
  }

  setup :set_mox_global

  setup do
    setup_chunk_registry(ChunkRegistryStub, false)
  end

  test "init/1" do
    assert init(nil) == {:ok, nil}

    ets_table_name = ChunkRegistryStub.ets_table_name()

    assert ets_table_exists?(ets_table_name)
    assert ETS.get_all(ets_table_name) == @items
  end

  describe "lookup_page/1" do
    setup do
      init(nil)
      :ok
    end

    test "page entry exists" do
      assert lookup_page(:module_a) == [
               "AAAAAAAA",
               "CCCCCCCC"
             ]
    end

    test "page preloads no chunk" do
      assert lookup_page(:module_b) == []
    end

    test "page entry doesn't exist" do
      assert_raise KeyError, "key {:page, :module_c} not found in the PLT", fn ->
        lookup_page(:module_c)
      end
    end
  end

  describe "lookup_term/1" do
    setup do
      init(nil)
      :ok
    end

    test "term holding a struct of a type that has no chunk" do
      assert lookup_term(1..3) == []
    end

    test "term holding no struct" do
      assert lookup_term(%{a: [1, {:b, "c"}]}) == []
    end

    test "term holding structs of a type that has chunks" do
      assert lookup_term([~D[2026-10-05], ~D[2026-10-06]]) == [
               "BBBBBBBB",
               "CCCCCCCC"
             ]
    end

    test "term holding structs of two types that share a chunk" do
      assert lookup_term(%{date: ~D[2026-10-05], times: [~T[12:34:56]]}) == [
               "AAAAAAAA",
               "BBBBBBBB",
               "CCCCCCCC"
             ]
    end
  end

  describe "lookup_type/1" do
    setup do
      init(nil)
      :ok
    end

    test "type entry exists" do
      assert lookup_type(Date) == ["BBBBBBBB", "CCCCCCCC"]
    end

    test "type entry doesn't exist" do
      assert lookup_type(Range) == []
    end
  end

  test "reload/0" do
    ChunkRegistry.start_link([])

    ets_table_name = ChunkRegistryStub.ets_table_name()
    ETS.put(ets_table_name, :dummy_key, :dummy_value)

    reload()

    assert ETS.get_all(ets_table_name) == @items
  end

  test "start_link/1" do
    assert {:ok, pid} = ChunkRegistry.start_link([])
    assert is_pid(pid)
    assert ets_table_exists?(ChunkRegistryStub.ets_table_name())
  end

  describe "struct_types/1" do
    test "improper list" do
      assert struct_types([~D[2026-10-05] | ~T[12:34:56]]) == MapSet.new([Date, Time])
    end

    test "list" do
      assert struct_types([~D[2026-10-05], 1, ~T[12:34:56]]) == MapSet.new([Date, Time])
    end

    test "map key" do
      assert struct_types(%{~D[2026-10-05] => 1}) == MapSet.new([Date])
    end

    test "map value" do
      assert struct_types(%{a: ~D[2026-10-05]}) == MapSet.new([Date])
    end

    test "no struct" do
      assert struct_types(%{a: [1, {:b, "c"}], d: 2.0, e: nil}) == MapSet.new()
    end

    test "struct" do
      assert struct_types(~D[2026-10-05]) == MapSet.new([Date])
    end

    test "struct field" do
      assert struct_types(Date.range(~D[2026-10-05], ~D[2026-10-06])) ==
               MapSet.new([Date, Date.Range])
    end

    test "struct in a list in a map in a struct" do
      term = MapSet.new([%{a: [~T[12:34:56]]}])

      assert struct_types(term) == MapSet.new([MapSet, Time])
    end

    test "the same type more than once" do
      assert struct_types({~D[2026-10-05], [~D[2026-10-06]]}) == MapSet.new([Date])
    end

    test "tuple" do
      assert struct_types({~D[2026-10-05], 1, ~T[12:34:56]}) == MapSet.new([Date, Time])
    end

    test "value an anonymous function captures" do
      date = ~D[2026-10-05]

      assert struct_types(fn -> date end) == MapSet.new()
    end
  end
end
