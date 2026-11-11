defmodule Hologram.Template.RendererFromQueryTest do
  # async: false - the tests write the query cache's persistent term (QueryCache.init/1), shared by
  # the whole node.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.DB.EntityOperations, only: [create: 1]
  import Hologram.Template.Renderer
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.DB.QueryCache
  alias Hologram.Server
  alias Hologram.Template.Renderer
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Template.Renderer.Module128
  alias Hologram.Test.Fixtures.Template.Renderer.Module140

  use_module_stub :chunk_registry
  use_module_stub :query_cache

  setup :set_mox_global

  setup do
    setup_chunk_registry(ChunkRegistryStub)
    setup_query_cache(QueryCacheStub, false)

    dump_query_cache(QueryCacheStub, [Module140, Module128])

    QueryCache.init(nil)

    :ok
  end

  @env %Renderer.Env{}
  @server %Server{}

  test "rejects template values for from_query props" do
    for name <- ["banana", "cherry"] do
      {:ok, _entity} =
        %{a: true, c: name}
        |> Entity2.new()
        |> create()
    end

    node = {:component, Module140, [{"entities", [expression: {[:template_value]}]}], []}

    assert {"entities = banana,cherry", %{}, @server} = render_dom(node, @env, @server)
  end

  test "raises when a like-named prop is missing" do
    node = {:component, Module128, [], []}

    expected_msg =
      "from_query for prop :entities in Hologram.Test.Fixtures.Template.Renderer.Module128 binds argument :missing_prop - no like-named prop is set"

    assert_error ArgumentError, expected_msg, fn ->
      render_dom(node, @env, @server)
    end
  end
end
