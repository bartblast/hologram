defmodule Hologram.Router.PageModuleResolverTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Router.PageModuleResolver
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.PLT
  alias Hologram.Router.PageModuleResolver
  alias Hologram.Router.SearchTree
  alias Hologram.Test.Fixtures.Router.Module2
  alias Hologram.Test.Fixtures.Router.PageModuleResolver.Module1

  use_module_stub :page_module_resolver

  setup :set_mox_global

  setup do
    setup_page_module_resolver(PageModuleResolverStub, false)
  end

  # Replaces the stub's dump with the given module info PLT entries.
  defp write_dump(items) do
    plt = PLT.start(items: items)
    PLT.dump(plt, PageModuleResolverStub.dump_path())
    PLT.stop(plt)
  end

  test "dump_path/0" do
    assert String.ends_with?(dump_path(), "/module_info.plt")
  end

  test "init/1" do
    assert init(nil) == {:ok, nil}

    search_tree = :persistent_term.get(PageModuleResolverStub.persistent_term_key())

    assert %SearchTree.Node{
             value: nil,
             children: %{
               "hologram-test-fixtures-router-pagemoduleresolver-module1" => %SearchTree.Node{
                 value: Module1,
                 children: %{}
               }
             }
           } = search_tree
  end

  test "init/1 routes the pages the dump holds, without asking the modules what they are" do
    # A component, which the dump presents as a page: only the dump can make it routable.
    write_dump([{Module2, %{page?: true, route: "/from-the-dump"}}])

    init(nil)

    assert resolve("/from-the-dump") == Module2
    refute resolve("/hologram-test-fixtures-router-pagemoduleresolver-module1")
  end

  test "init/1 loads the pages it routes" do
    :code.purge(Module1)
    :code.delete(Module1)
    refute :code.is_loaded(Module1)

    init(nil)

    assert :code.is_loaded(Module1)
  end

  test "init/1 asks a page for its route when the dump does not hold it" do
    write_dump([{Module1, %{page?: true, route: nil}}])

    init(nil)

    assert resolve("/hologram-test-fixtures-router-pagemoduleresolver-module1") == Module1
  end

  test "init/1 skips a page whose module cannot be loaded" do
    write_dump([{Aaa.Bbb, %{page?: true, route: "/no-such-module"}}])

    init(nil)

    refute resolve("/no-such-module")
  end

  test "init/1 skips entries that are not pages" do
    write_dump([
      {Module1,
       %{page?: true, route: "/hologram-test-fixtures-router-pagemoduleresolver-module1"}},
      {Module2, %{page?: false, route: "/not-a-page"}}
    ])

    init(nil)

    assert resolve("/hologram-test-fixtures-router-pagemoduleresolver-module1") == Module1
    refute resolve("/not-a-page")
  end

  test "init/1 reads no BEAM file" do
    :erlang.trace_pattern({:beam_lib, :chunks, 2}, true, [:call_count])

    try do
      init(nil)

      assert :erlang.trace_info({:beam_lib, :chunks, 2}, :call_count) == {:call_count, 0}
    after
      :erlang.trace_pattern({:beam_lib, :chunks, 2}, false, [:call_count])
    end
  end

  test "init/1 raises when there is no dump" do
    File.rm!(PageModuleResolverStub.dump_path())

    assert_raise File.Error, fn -> init(nil) end
  end

  test "reload/0" do
    key = PageModuleResolverStub.persistent_term_key()
    :persistent_term.put(key, :dummy_value)

    reload()

    assert %SearchTree.Node{
             value: nil,
             children: %{
               "hologram-test-fixtures-router-pagemoduleresolver-module1" => %SearchTree.Node{
                 value: Module1,
                 children: %{}
               }
             }
           } = :persistent_term.get(key)
  end

  describe "resolve/2" do
    setup do
      init(nil)
      :ok
    end

    test "there is a matching route" do
      request_path = "/hologram-test-fixtures-router-pagemoduleresolver-module1"
      assert resolve(request_path) == Module1
    end

    test "there is no matching route" do
      request_path = "/unknown-path"
      refute resolve(request_path)
    end
  end

  test "start_link/1" do
    assert {:ok, pid} = PageModuleResolver.start_link([])
    assert is_pid(pid)
    assert persistent_term_exists?(PageModuleResolverStub.persistent_term_key())
  end
end
