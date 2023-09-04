defmodule Hologram.Runtime.RouterTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Router
  alias Hologram.Router.SearchTree

  test "init/1" do
    persistent_term_name = random_atom()

    assert {:ok, nil} = init(persistent_term_name)

    search_tree = :persistent_term.get(persistent_term_name)

    assert %SearchTree.Node{
             value: nil,
             children: %{
               "hologram-test-fixtures-runtime-router-module1" => %SearchTree.Node{
                 value: Hologram.Test.Fixtures.Runtime.Router.Module1,
                 children: %{}
               }
             }
           } = search_tree
  end
end
