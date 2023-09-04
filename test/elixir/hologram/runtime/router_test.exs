defmodule Hologram.Runtime.RouterTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Router
  alias Hologram.Router.SearchTree

  test "start_link/1" do
    name = random_atom()

    assert {:ok, pid} = start_link(name)
    assert is_pid(pid)

    assert ets_table_exists?(name)
    assert :ets.whereis(name)

    ets_info = :ets.info(name)
    assert ets_info[:named_table]
    assert ets_info[:protection] == :public
    assert ets_info[:read_concurrency]

    [{:search_tree, search_tree}] = :ets.lookup(name, :search_tree)

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
