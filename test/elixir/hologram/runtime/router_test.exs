defmodule Hologram.Runtime.RouterTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Router

  alias Hologram.Router.SearchTree
  alias Hologram.Test.Fixtures.Runtime.Router.Module1
  alias Hologram.Test.Fixtures.Runtime.Router.Module3

  test "extract_params/2" do
    url_path = "/hologram-test-fixtures-runtime-router-module3/111/ccc/222"

    assert extract_params(url_path, Module3) == %{aaa: "111", bbb: "222"}
  end

  test "init/1" do
    persistent_term_key = random_atom()

    assert {:ok, nil} = init(persistent_term_key)

    search_tree = :persistent_term.get(persistent_term_key)

    assert %SearchTree.Node{
             value: nil,
             children: %{
               "hologram-test-fixtures-runtime-router-module1" => %SearchTree.Node{
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
      url_path = "/hologram-test-fixtures-runtime-router-module1"
      assert resolve_page(url_path, persistent_term_key) == Module1
    end

    test "there is no matching route", %{persistent_term_key: persistent_term_key} do
      url_path = "/unknown-path"
      refute resolve_page(url_path, persistent_term_key)
    end
  end
end
