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

    test "term holding a module that is no struct type" do
      assert lookup_term(%{calendar: Calendar.ISO}) == []
    end

    test "term holding a struct of a type that has no chunk" do
      assert lookup_term(1..3) == []
    end

    test "term holding no struct and no module" do
      assert lookup_term(%{a: [1, {:b, "c"}]}) == []
    end

    # Client code can build a struct of the type from the module alone.
    test "term holding the module of a type that has chunks" do
      assert lookup_term(%{type: Date}) == ["BBBBBBBB", "CCCCCCCC"]
    end

    test "term holding the modules of two types that share a chunk" do
      assert lookup_term([Date, Time]) == ["AAAAAAAA", "BBBBBBBB", "CCCCCCCC"]
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

  # The structs are ranges, which hold no module but their own. A date holds its calendar's too.
  describe "named_modules/1" do
    test "atom that is no module's name" do
      assert named_modules(:ok) == MapSet.new()
    end

    test "improper list" do
      assert named_modules([1..2 | Date]) == MapSet.new([Date, Range])
    end

    test "list" do
      assert named_modules([1..2, 1, Date]) == MapSet.new([Date, Range])
    end

    test "map key" do
      assert named_modules(%{Date => 1, (1..2) => 2}) == MapSet.new([Date, Range])
    end

    test "map value" do
      assert named_modules(%{a: Date, b: 1..2}) == MapSet.new([Date, Range])
    end

    test "module" do
      assert named_modules(Date) == MapSet.new([Date])
    end

    test "module that is no struct type" do
      assert named_modules(Calendar.ISO) == MapSet.new([Calendar.ISO])
    end

    test "no struct and no module" do
      assert named_modules(%{a: [1, {:b, "c"}], d: 2.0, e: nil, f: true}) == MapSet.new()
    end

    test "struct" do
      assert named_modules(1..2) == MapSet.new([Range])
    end

    test "struct field" do
      assert named_modules(Date.range(~D[2026-10-05], ~D[2026-10-06])) ==
               MapSet.new([Calendar.ISO, Date, Date.Range])
    end

    test "struct in a list in a map in a struct" do
      term = MapSet.new([%{a: [1..2]}])

      assert named_modules(term) == MapSet.new([MapSet, Range])
    end

    test "the same module more than once" do
      assert named_modules({1..2, [3..4], Range}) == MapSet.new([Range])
    end

    test "tuple" do
      assert named_modules({1..2, 1, Date}) == MapSet.new([Date, Range])
    end

    test "value an anonymous function captures" do
      range = 1..2

      assert named_modules(fn -> {range, Date} end) == MapSet.new()
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
end
