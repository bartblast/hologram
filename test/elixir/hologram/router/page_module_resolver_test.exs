defmodule Hologram.Router.PageModuleResolverTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Router.PageModuleResolver
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Router.PageModuleResolver
  alias Hologram.Router.SearchTree
  alias Hologram.Test.Fixtures.Router.PageModuleResolver.Module1

  use_module_stub :page_module_resolver

  setup :set_mox_global

  setup do
    setup_page_module_resolver(PageModuleResolverStub, false)
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
