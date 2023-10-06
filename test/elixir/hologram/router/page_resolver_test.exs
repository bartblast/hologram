defmodule Hologram.Router.PageResolverTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Router.PageResolver
  import Mox

  alias Hologram.Router.PageResolver
  alias Hologram.Router.SearchTree
  alias Hologram.Test.Fixtures.Router.PageResolver.Module1

  defmodule Stub do
    @behaviour PageResolver

    def persistent_term_key, do: __MODULE__
  end

  setup :set_mox_global

  setup do
    stub_with(PageResolver.Mock, Stub)
    :ok
  end

  test "init/1" do
    assert {:ok, nil} = init(nil)

    search_tree = :persistent_term.get(Stub.persistent_term_key())

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
      init(nil)
      :ok
    end

    test "there is a matching route" do
      request_path = "/hologram-test-fixtures-router-pageresolver-module1"
      assert resolve(request_path) == Module1
    end

    test "there is no matching route" do
      request_path = "/unknown-path"
      refute resolve(request_path)
    end
  end

  test "start_link/1" do
    assert {:ok, pid} = start_link([])
    assert is_pid(pid)
    assert persistent_term_exists?(Stub.persistent_term_key())
  end
end
