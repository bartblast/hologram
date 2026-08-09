defmodule Hologram.DB.QueryCacheTest do
  use Hologram.Test.DatabaseCase, async: false
  use Hologram.Query

  import Hologram.DB.QueryCache
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryCompiler
  alias Hologram.Query
  alias Hologram.Query.Param
  alias Hologram.Query.Registry
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Component.Module11
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  use_module_stub :query_cache

  setup :set_mox_global

  setup do
    setup_query_cache(QueryCacheStub, false)
  end

  defp expected_data do
    %{entries: expected_entries(), prop_params: %{{Module11, :entities} => [:min_b]}}
  end

  defp expected_entries do
    module_1_term =
      Entity2
      |> filter(a: true)
      |> order_by(:c)
      |> Query.normalize()

    module_11_term =
      Entity2
      |> filter(b: {:>=, %Param{name: :min_b}})
      |> Query.normalize()

    ordered_pairs = MapSet.new([{Entity2, :c}])
    mapping = Mapper.derive!(Reflection.list_entities(), ordered_pairs)

    [module_1_term, module_11_term]
    |> Registry.build()
    |> Map.new(fn {id, entry} ->
      {id, Map.put(entry, :compiled, QueryCompiler.compile(entry.term, mapping))}
    end)
  end

  test "entries/0" do
    init(nil)

    assert entries() == expected_entries()
  end

  describe "fetch/1" do
    test "returns the entry for a registered query id" do
      init(nil)

      [{id, entry} | _other_entries] = Enum.to_list(expected_entries())

      assert fetch(id) == {:ok, entry}
    end

    test "returns :error for an unknown query id" do
      init(nil)

      assert fetch("unknown") == :error
    end
  end

  test "init/1" do
    assert init(nil) == {:ok, nil}

    assert :persistent_term.get(QueryCacheStub.persistent_term_key()) == expected_data()
  end

  describe "prop_params/2" do
    test "returns the argument names of a parameterized from_query prop" do
      init(nil)

      assert prop_params(Module11, :entities) == [:min_b]
    end

    test "returns nil for a prop without registered params" do
      init(nil)

      assert prop_params(Module11, :unknown) == nil
    end
  end

  test "reload/0" do
    init(nil)

    key = QueryCacheStub.persistent_term_key()
    :persistent_term.put(key, :dummy_value)

    reload()

    assert :persistent_term.get(key) == expected_data()
  end
end
