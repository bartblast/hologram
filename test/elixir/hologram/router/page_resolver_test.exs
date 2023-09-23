defmodule Hologram.Router.PageResolverTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Router.PageResolver

  alias Hologram.Router.SearchTree
  alias Hologram.Test.Fixtures.Router.PageResolver.Module1

  test "init/1" do
    store_key = random_atom()

    assert {:ok, nil} = init(store_key)

    search_tree = :persistent_term.get(store_key)

    assert %SearchTree.Node{
             value: nil,
             children: %{
               "hologram-test-fixtures-router-page-resolver-module1" => %SearchTree.Node{
                 value: Module1,
                 children: %{}
               }
             }
           } = search_tree
  end

  describe "resolve/2" do
    setup do
      store_key = random_atom()
      init(store_key)

      [store_key: store_key]
    end

    test "there is a matching route", %{store_key: store_key} do
      request_path = "/hologram-test-fixtures-router-page-resolver-module1"
      assert resolve(request_path, store_key) == Module1
    end

    test "there is no matching route", %{store_key: store_key} do
      request_path = "/unknown-path"
      refute resolve(request_path, store_key)
    end
  end

  test "start_link/1" do
    store_key = random_atom()

    assert {:ok, pid} = start_link(store_key: store_key)
    assert is_pid(pid)
    assert persistent_term_exists?(store_key)
  end
end
