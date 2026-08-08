defmodule Hologram.Template.RendererFromQueryTest do
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Database.EntityOperations, only: [create: 1]
  import Hologram.Template.Renderer
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Database.QueryCache
  alias Hologram.Entity
  alias Hologram.Server
  alias Hologram.Template.Renderer
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Template.Renderer.Module88
  alias Hologram.Test.Fixtures.Template.Renderer.Module89
  alias Hologram.Test.Fixtures.Template.Renderer.Module90

  use_module_stub :query_cache

  setup :set_mox_global

  setup do
    setup_query_cache(QueryCacheStub, false)

    stub(QueryCacheMock, :component_modules, fn -> [Module88, Module89, Module90] end)
    QueryCache.init(nil)

    :ok
  end

  @env %Renderer.Env{}
  @server %Server{}

  defp create_entities do
    Entity2
    |> Entity.new(a: true, c: "banana")
    |> create()

    Entity2
    |> Entity.new(a: false, b: 3, c: "apple")
    |> create()

    Entity2
    |> Entity.new(a: true, b: 7, c: "cherry")
    |> create()
  end

  test "injects a parameterized from_query prop bound to a like-named prop" do
    create_entities()

    node = {:component, Module89, [{"min_b", [expression: {5}]}], []}

    assert {"entities = cherry", %{}, @server} = render_dom(node, @env, @server)
  end

  test "injects a zero-arity from_query prop" do
    create_entities()

    node = {:component, Module88, [], []}

    assert {"entities = banana,cherry", %{}, @server} = render_dom(node, @env, @server)
  end

  test "rejects template values for from_query props" do
    create_entities()

    node = {:component, Module88, [{"entities", [expression: {[:template_value]}]}], []}

    assert {"entities = banana,cherry", %{}, @server} = render_dom(node, @env, @server)
  end

  test "raises when a like-named prop is missing" do
    create_entities()

    node = {:component, Module90, [], []}

    expected_msg =
      "from_query for prop :entities in Hologram.Test.Fixtures.Template.Renderer.Module90 binds argument :missing_prop - no like-named prop is set"

    assert_error ArgumentError, expected_msg, fn ->
      render_dom(node, @env, @server)
    end
  end
end
