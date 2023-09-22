defmodule Hologram.Runtime.Router.ProcessTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Router.Process

  alias Hologram.Router.SearchTree
  alias Hologram.Test.Fixtures.Runtime.Router.Process.Module1

  test "default_persistent_term_key/0" do
    assert default_persistent_term_key() == {Hologram.Router.Process, :search_tree}
  end

  test "init/1" do
    persistent_term_key = random_atom()

    assert {:ok, nil} = init(persistent_term_key)

    search_tree = :persistent_term.get(persistent_term_key)

    assert %SearchTree.Node{
             value: nil,
             children: %{
               "hologram-test-fixtures-runtime-router-process-module1" => %SearchTree.Node{
                 value: Module1,
                 children: %{}
               }
             }
           } = search_tree
  end

  describe "resolve_page/2" do
    setup do
      persistent_term_key = random_atom()
      init(persistent_term_key)

      [persistent_term_key: persistent_term_key]
    end

    test "there is a matching route", %{persistent_term_key: persistent_term_key} do
      request_path = "/hologram-test-fixtures-runtime-router-process-module1"
      assert resolve_page(request_path, persistent_term_key) == Module1
    end

    test "there is no matching route", %{persistent_term_key: persistent_term_key} do
      request_path = "/unknown-path"
      refute resolve_page(request_path, persistent_term_key)
    end
  end

  test "start_link/1" do
    persistent_term_key = random_atom()

    assert {:ok, pid} = start_link(persistent_term_key: persistent_term_key)
    assert is_pid(pid)
    assert persistent_term_exists?(persistent_term_key)
  end
end
