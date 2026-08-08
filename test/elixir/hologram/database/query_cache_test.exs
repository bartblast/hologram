defmodule Hologram.Database.QueryCacheTest do
  use Hologram.Test.BasicCase, async: false
  use Hologram.Query

  import Hologram.Database.QueryCache
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Database
  alias Hologram.Database.QueryCache
  alias Hologram.Database.QueryCompiler
  alias Hologram.Query
  alias Hologram.Query.Registry
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  use_module_stub :query_cache

  setup :set_mox_global

  setup do
    setup_query_cache(QueryCacheStub, false)
  end

  defp expected_entries do
    term =
      Entity2
      |> filter(a: true)
      |> order_by(:c)
      |> Query.normalize()

    compiled = QueryCompiler.compile(term, Database.mapping())

    [term]
    |> Registry.build()
    |> Map.new(fn {id, entry} -> {id, Map.put(entry, :compiled, compiled)} end)
  end

  test "entries/0" do
    init(nil)

    assert entries() == expected_entries()
  end

  describe "fetch/1" do
    test "returns the entry for a registered query id" do
      init(nil)

      [{id, entry}] = Enum.to_list(expected_entries())

      assert fetch(id) == {:ok, entry}
    end

    test "returns :error for an unknown query id" do
      init(nil)

      assert fetch("unknown") == :error
    end
  end

  test "init/1" do
    assert init(nil) == {:ok, nil}

    assert :persistent_term.get(QueryCacheStub.persistent_term_key()) == expected_entries()
  end

  test "reload/0" do
    QueryCache.start_link([])

    key = QueryCacheStub.persistent_term_key()
    :persistent_term.put(key, :dummy_value)

    reload()

    assert :persistent_term.get(key) == expected_entries()
  end
end
