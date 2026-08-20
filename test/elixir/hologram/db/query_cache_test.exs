defmodule Hologram.DB.QueryCacheTest do
  use Hologram.Test.DatabaseCase, async: false
  use Hologram.Query

  import Hologram.DB.QueryCache
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Auth
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryCompiler
  alias Hologram.Query
  alias Hologram.Query.Placeholder
  alias Hologram.Query.Registry
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Component.Module11
  alias Hologram.Test.Fixtures.Component.Module15
  alias Hologram.Test.Fixtures.Component.Module16
  alias Hologram.Test.Fixtures.Component.Module17
  alias Hologram.Test.Fixtures.Component.Module18
  alias Hologram.Test.Fixtures.Component.Module19
  alias Hologram.Test.Fixtures.Component.Module20
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

    sort_key_attributes = MapSet.new([{Entity2, :c}])
    mapping = Mapper.derive!(Reflection.list_entities(), sort_key_attributes)

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

  test "init/1 populates against a virgin database" do
    {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_system" CASCADE))
    {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))

    assert init(nil) == {:ok, nil}

    assert :persistent_term.get(QueryCacheStub.persistent_term_key()) == expected_data()
  end

  test "init/1 raises for a registered query whose root type declares no allow lines" do
    stub(QueryCacheMock, :component_modules, fn -> [Module15] end)

    expected_msg =
      "the registered query in Hologram.Test.Fixtures.Component.Module15 reads " <>
        "Hologram.Test.Fixtures.Entity.Module1, which declares no allow lines - " <>
        "default deny returns no rows to any session. Add allow lines, or drop the query."

    assert_error Hologram.CompileError, expected_msg, fn ->
      init(nil)
    end
  end

  test "init/1 raises for a registered query whose include target declares no allow lines" do
    stub(QueryCacheMock, :component_modules, fn -> [Module16] end)

    expected_msg =
      "the registered query in Hologram.Test.Fixtures.Component.Module16 includes " <>
        "Hologram.Test.Fixtures.Entity.Module1, which declares no allow lines - " <>
        "default deny leaves the embed empty in every row. Add allow lines, or drop the include."

    assert_error Hologram.CompileError, expected_msg, fn ->
      init(nil)
    end
  end

  test "init/1 populates a registered query that reads a type with server-only attributes without referencing them" do
    stub(QueryCacheMock, :component_modules, fn -> [Module20] end)

    assert init(nil) == {:ok, nil}
  end

  test "init/1 raises for a registered query filtering on a server-only attribute" do
    stub(QueryCacheMock, :component_modules, fn -> [Module17] end)

    expected_msg =
      "the registered query in Hologram.Test.Fixtures.Component.Module17 filters or orders on " <>
        "server_only attributes (Hologram.Test.Fixtures.Entity.Module15 :token) - the client " <>
        "never holds those values, so it could not evaluate the reference locally. Drop the " <>
        "reference, or read the rows through the trusted backend API."

    assert_error Hologram.CompileError, expected_msg, fn ->
      init(nil)
    end
  end

  test "init/1 raises for a registered query ordering on a server-only attribute" do
    stub(QueryCacheMock, :component_modules, fn -> [Module18] end)

    expected_msg =
      "the registered query in Hologram.Test.Fixtures.Component.Module18 filters or orders on " <>
        "server_only attributes (Hologram.Test.Fixtures.Entity.Module15 :token) - the client " <>
        "never holds those values, so it could not evaluate the reference locally. Drop the " <>
        "reference, or read the rows through the trusted backend API."

    assert_error Hologram.CompileError, expected_msg, fn ->
      init(nil)
    end
  end

  test "init/1 raises for a registered query filtering on a server-only attribute inside an include" do
    stub(QueryCacheMock, :component_modules, fn -> [Module19] end)

    expected_msg =
      "the registered query in Hologram.Test.Fixtures.Component.Module19 filters or orders on " <>
        "server_only attributes (Hologram.Test.Fixtures.Entity.Module15 :token) - the client " <>
        "never holds those values, so it could not evaluate the reference locally. Drop the " <>
        "reference, or read the rows through the trusted backend API."

    assert_error Hologram.CompileError, expected_msg, fn ->
      init(nil)
    end
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

  test "reload/0" do
    init(nil)

    key = QueryCacheStub.persistent_term_key()
    :persistent_term.put(key, :dummy_value)

    reload()

    assert :persistent_term.get(key) == expected_data()
  end
end
