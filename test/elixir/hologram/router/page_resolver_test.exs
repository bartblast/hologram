defmodule Hologram.Router.PageResolverTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Router.PageResolver

  alias Hologram.Router.SearchTree
  alias Hologram.Test.Fixtures.Router.PageResolver.Module1

  test "init/1" do
    persistent_term_key = random_atom()

    assert {:ok, nil} = init(persistent_term_key)

    search_tree = :persistent_term.get(persistent_term_key)

    assert %SearchTree.Node{
             value: nil,
             children: %{
               "hologram-test-fixtures-router-pageresolver-module1" => %SearchTree.Node{
                 value: Module1,
                 children: %{}
               }
             }
           } = search_tree
  end

  describe "resolve/2" do
    setup do
      persistent_term_key = random_atom()
      init(persistent_term_key)

      [persistent_term_key: persistent_term_key]
    end

    test "there is a matching route", %{persistent_term_key: persistent_term_key} do
      request_path = "/hologram-test-fixtures-router-pageresolver-module1"
      assert resolve(request_path, persistent_term_key) == Module1
    end

    test "there is no matching route", %{persistent_term_key: persistent_term_key} do
      request_path = "/unknown-path"
      refute resolve(request_path, persistent_term_key)
    end
  end

  test "start_link/1" do
    persistent_term_key = random_atom()

    assert {:ok, pid} = start_link(persistent_term_key: persistent_term_key)
    assert is_pid(pid)
    assert persistent_term_exists?(persistent_term_key)
  end
end
