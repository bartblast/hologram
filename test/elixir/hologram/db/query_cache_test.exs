defmodule Hologram.DB.QueryCacheTest do
  # async: false - the tests write the query cache's persistent term, shared by the whole node.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.DB.QueryCache
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.PLT
  alias Hologram.Entity.Derived
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Entity.Module33

  use_module_stub :query_cache

  setup :set_mox_global

  setup do
    setup_query_cache(QueryCacheStub, false)
    dump_query_cache(QueryCacheStub)
  end

  defp expected_data do
    %{
      derived: %{},
      permission_checking?: false,
      synced_types: Reflection.list_entities()
    }
  end

  test "init/1" do
    assert init(nil) == {:ok, nil}

    assert :persistent_term.get(QueryCacheStub.persistent_term_key()) == expected_data()
  end

  # Keyed by a name no fixture declares, so no other test can have put it.
  test "init/1 puts the derived definitions the build resolved where the runtime reads them" do
    PLT.start()
    |> PLT.put(derived: %{{Module33, :from_the_dump} => {:value, :dumped}})
    |> PLT.dump(QueryCacheStub.dump_path())

    init(nil)

    assert Derived.definition(Module33, :from_the_dump) == {:value, :dumped}
  end

  describe "permission_checking?/0" do
    test "returns true for a build with a page checking permissions on the client" do
      dump_query_cache(QueryCacheStub, true)

      init(nil)

      assert permission_checking?()
    end

    test "returns false for a build with no page checking permissions on the client" do
      init(nil)

      refute permission_checking?()
    end
  end

  test "synced_types/0" do
    dump_query_cache(QueryCacheStub, false, [Entity2, Module33])

    init(nil)

    assert synced_types() == [Entity2, Module33]
  end

  test "reload/0 picks up what the build has dumped since" do
    init(nil)

    key = QueryCacheStub.persistent_term_key()
    assert :persistent_term.get(key) == expected_data()

    # What live reload does: the recompile ahead of it rewrites the dump, and this reads it again.
    dump_query_cache(QueryCacheStub, false, [Entity2])

    reload()

    assert :persistent_term.get(key).synced_types == [Entity2]
  end

  test "dump_path/0 reads from the build directory" do
    assert dump_path() == Path.join([Reflection.build_dir(), "queries.plt"])
  end
end
