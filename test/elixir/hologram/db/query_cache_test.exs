defmodule Hologram.DB.QueryCacheTest do
  use Hologram.Test.DatabaseCase, async: false
  use Hologram.Query

  import Hologram.DB.QueryCache
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Auth
  alias Hologram.DB.Connection
  alias Hologram.Query
  alias Hologram.Query.Placeholder
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
    entries = expected_entries()

    %{
      entries: entries,
      prop_params: %{{Module11, :entities} => [:min_b]},
      windows: expected_windows(entries)
    }
  end

  # The grants window rides with every build's windows, whether or not a page subscribes to it -
  # the build decides who asks, this is only where an id resolves back to a term.
  defp expected_windows(entries) do
    grants_window = Auth.grants_window()

    entries
    |> Map.new(fn {_id, entry} -> {entry.window_id, entry.window} end)
    |> Map.put(Registry.id(grants_window), grants_window)
  end

  defp expected_entries do
    module_1_term =
      Entity2
      |> filter(a: true)
      |> order_by(:c)
      |> Query.normalize()

    module_11_term =
      Entity2
      |> filter(b: {:>=, %Placeholder{name: :min_b}})
      |> Query.normalize()

    Registry.build([module_1_term, module_11_term])
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

  test "init/1 populates against a virgin database" do
    {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_system" CASCADE))
    {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))

    assert init(nil) == {:ok, nil}

    assert :persistent_term.get(QueryCacheStub.persistent_term_key()) == expected_data()
  end

  describe "prop_params/2" do
    test "returns the argument names of a parameterized from_query prop" do
      init(nil)

      assert prop_params(Module11, :entities) == [:min_b]
    end

    test "returns nil for a prop without registered placeholders" do
      init(nil)

      assert prop_params(Module11, :unknown) == nil
    end
  end

  describe "window/1" do
    test "returns the term a registered window downloads" do
      init(nil)

      [{_id, entry} | _other_entries] = Enum.to_list(expected_entries())

      assert window(entry.window_id) == entry.window
    end

    # Registered whether or not anything subscribes: the build decides which pages check
    # permissions locally, and a client the build told to ask must find a term here.
    test "returns the grants window a client checking permissions locally downloads" do
      init(nil)

      grants_window = Auth.grants_window()

      assert window(Registry.id(grants_window)) == grants_window
    end

    test "returns nil for an id nothing downloads" do
      init(nil)

      assert window("unknown") == nil
    end
  end

  test "reload/0 picks up the queries the build has dumped since" do
    init(nil)

    key = QueryCacheStub.persistent_term_key()
    assert :persistent_term.get(key) == expected_data()

    # What live reload does: the recompile ahead of it rewrites the dump, and this reads it again.
    dump_query_cache(QueryCacheStub, [Module11])

    reload()

    reloaded = :persistent_term.get(key)

    assert reloaded != expected_data()
    assert reloaded.prop_params == %{{Module11, :entities} => [:min_b]}
  end

  test "dump_path/0 reads from the build directory" do
    assert dump_path() == Path.join([Reflection.build_dir(), "queries.plt"])
  end
end
