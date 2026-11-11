defmodule Hologram.Template.RendererDerivedTest do
  # async: false - the tests write the query cache's persistent term (QueryCache.init/1) and
  # restart the asset path registry under its registered name, both shared by the whole node.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.DB.EntityOperations, only: [create: 1]
  import Hologram.Template.Renderer
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Auth
  alias Hologram.Auth.Context
  alias Hologram.Commons.ETS
  alias Hologram.DB
  alias Hologram.DB.QueryCache
  alias Hologram.Entity.NotIncluded
  alias Hologram.Server
  alias Hologram.Sync.Carry
  alias Hologram.Template.Renderer
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Entity.Module25
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyEntity
  alias Hologram.Test.Fixtures.Template.Renderer.Module144
  alias Hologram.Test.Fixtures.Template.Renderer.Module145
  alias Hologram.Test.Fixtures.Template.Renderer.Module146
  alias Hologram.Test.Fixtures.Template.Renderer.Module147
  alias Hologram.Test.Fixtures.Template.Renderer.Module148
  alias Hologram.Test.Fixtures.Template.Renderer.Module149
  alias Hologram.Test.Fixtures.Template.Renderer.Module150
  alias Hologram.Test.Fixtures.Template.Renderer.Module151
  alias Hologram.Test.Fixtures.Template.Renderer.Module152
  alias Hologram.Test.Fixtures.Template.Renderer.Module153
  alias Hologram.Test.Fixtures.Template.Renderer.Module154
  alias Hologram.Test.Fixtures.Template.Renderer.Module155
  alias Hologram.Test.Fixtures.Template.Renderer.Module156
  alias Hologram.Test.Fixtures.Template.Renderer.Module157
  alias Hologram.Test.Fixtures.Template.Renderer.Module158
  alias Hologram.Test.Fixtures.Template.Renderer.Module160

  use_module_stub :asset_path_registry
  use_module_stub :chunk_registry
  use_module_stub :page_digest_registry
  use_module_stub :query_cache

  setup :set_mox_global

  setup do
    setup_chunk_registry(ChunkRegistryStub)
    setup_query_cache(QueryCacheStub, false)

    dump_query_cache(QueryCacheStub, [])

    QueryCache.init(nil)

    :ok
  end

  @env %Renderer.Env{}
  @server %Server{}

  defp create_entities do
    {:ok, _entity} =
      %{a: true, c: "banana"}
      |> Entity2.new()
      |> create()

    {:ok, _entity} =
      %{a: false, b: 3, c: "apple"}
      |> Entity2.new()
      |> create()

    {:ok, _entity} =
      %{a: true, b: 7, c: "cherry"}
      |> Entity2.new()
      |> create()
  end

  defp stateful_node(module, props_dom \\ []) do
    {:component, module, [{"cid", [text: "my_component"]} | props_dom], []}
  end

  describe "stateful component" do
    test "hands init the fields reading only props" do
      node = stateful_node(Module144, [{"first_name", [text: "Ada"]}])

      assert {"seen = Hi Ada", _component_registry, _server_struct} =
               render_dom(node, @env, @server)
    end

    test "hands init a placeholder for a field reading state" do
      not_computed =
        "#Hologram.Component.NotComputed&lt;:double reads state, so it&#39;s computed after init&gt;"

      assert {html, _component_registry, _server_struct} =
               render_dom(stateful_node(Module153), @env, @server)

      assert html == "pending = #{not_computed}"
    end

    test "computes a field reading state from the state init returned" do
      assert {"shout = Hi!", _component_registry, _server_struct} =
               render_dom(stateful_node(Module154), @env, @server)
    end

    test "computes a field reading state from the state defaults when init returns only the server struct" do
      assert {"double = 6", _component_registry, _server_struct} =
               render_dom(stateful_node(Module155), @env, @server)
    end

    test "computes a field reading state once" do
      Process.delete(:module_145_computations)

      assert {"double = 10", _component_registry, _server_struct} =
               render_dom(stateful_node(Module145), @env, @server)

      assert Process.get(:module_145_computations) == 1
    end

    test "holds the derived fields in the struct" do
      {_html, component_registry, _server_struct} =
        render_dom(stateful_node(Module154), @env, @server)

      assert component_registry["my_component"].struct.derived == %{shout: "Hi!"}
    end

    test "raises when init stores a derived field before it is computed" do
      expected_msg =
        "init/3 of Hologram.Test.Fixtures.Template.Renderer.Module148 stored derived field :double in state :copy before it was computed - it reads state, so it's computed after init"

      assert_error Hologram.StateError, expected_msg, fn ->
        render_dom(stateful_node(Module148), @env, @server)
      end
    end
  end

  describe "stateless component" do
    test "computes the fields from its props" do
      node = {:component, Module146, [{"name", [text: "ada"]}], []}

      assert render_dom(node, @env, @server) == {"ada [ADA]", %{}, @server}
    end

    test "computes a field from a prop the context set" do
      node = {:component, Module156, [], []}
      env = %Renderer.Env{context: %{{Module156, :theme} => "dark"}}

      assert render_dom(node, env, @server) == {"theme dark", %{}, @server}
    end

    test "raises on a field reading state" do
      node = {:component, Module147, [{"name", [text: "ada"]}], []}

      expected_msg =
        "derived field :shout in Hologram.Test.Fixtures.Template.Renderer.Module147 reads state :suffix, which a component rendered without a cid doesn't have - give it a cid"

      assert_error Hologram.StateError, expected_msg, fn ->
        render_dom(node, @env, @server)
      end
    end
  end

  describe "query" do
    test "renders the rows a field's query reads" do
      create_entities()

      node = {:component, Module149, [], []}

      assert render_dom(node, @env, @server) == {"entities = banana,cherry", %{}, @server}
    end

    test "carries the rows a field's query reads" do
      create_entities()

      Carry.start()

      render_dom({:component, Module149, [], []}, @env, @server)

      carried_names =
        nil
        |> Carry.take()
        |> Map.fetch!(:put_entity)
        |> Map.fetch!(inspect(Entity2))
        |> Enum.map(& &1.c)
        |> Enum.sort()

      assert carried_names == ["banana", "cherry"]
    end

    test "carries a count under the field's name and the arguments its function was given" do
      create_entities()

      Carry.start()

      node = {:component, Module150, [{"min_b", [expression: {5}]}], []}

      assert {"total = 1", _component_registry, _server_struct} = render_dom(node, @env, @server)
      assert Carry.take_counts() == %{"#{inspect(Module150)}/total/5" => 1}
    end

    test "renders only the rows the session user's policy grants" do
      %{priority: 1, public: true}
      |> PolicyEntity.new()
      |> DB.create!()

      private_entity =
        %{priority: 2, public: false}
        |> PolicyEntity.new()
        |> DB.create!()

      user =
        %{email: "renderer_derived_1@example.com"}
        |> Module14.new()
        |> DB.create!()

      Auth.grant_role(user, :viewer, private_entity)

      node = {:component, Module157, [], []}
      server_struct = %Server{user_id: user.id}

      assert {"entities = 1,2", %{}, ^server_struct} =
               Context.with_actor(user.id, fn -> render_dom(node, @env, server_struct) end)
    end

    test "renders only the unconditionally visible rows for an anonymous session" do
      %{priority: 1, public: true}
      |> PolicyEntity.new()
      |> DB.create!()

      %{priority: 2, public: false}
      |> PolicyEntity.new()
      |> DB.create!()

      assert render_dom({:component, Module157, [], []}, @env, @server) ==
               {"entities = 1", %{}, @server}
    end

    test "hands the template no relationship the query did not include" do
      {:ok, required} =
        %{a: ~D[2026-01-01], b: ~U[2026-01-01 00:00:00.000000Z], c: :x, d: 1.5}
        |> Module4.new()
        |> create()

      {:ok, shown} =
        %{public: true, title: "shown"}
        |> Module13.new()
        |> create()

      {:ok, _entity} =
        %{f_id: required.id, h_id: shown.id}
        |> Module25.new()
        |> create()

      not_included = inspect(%NotIncluded{relationship: :h})

      assert render_dom({:component, Module158, [], []}, @env, @server) ==
               {"h = #{not_included}", %{}, @server}
    end

    test "carries a count reading another field's rows under those rows" do
      create_entities()

      Carry.start()

      {_html, component_registry, _server_struct} =
        render_dom(stateful_node(Module151), @env, @server)

      ripe = component_registry["my_component"].struct.derived.ripe

      assert Carry.take_counts() == %{"#{inspect(Module151)}/ripe_total/#{inspect(ripe)}" => 2}
    end
  end

  describe "page" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_page_digest_registry(PageDigestRegistryStub)

      ETS.put(PageDigestRegistryStub.ets_table_name(), Module152, :dummy_module_152_digest)

      :ok
    end

    test "computes the fields from its params and state" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module160, :dummy_module_160_digest)

      %{tree: tree} = render_page(Module160, %{name: "ada"}, @server, initial_page?: true)

      assert print_dom(tree) == "layout ADA! page ada!"
    end

    test "hands the fields to the layout as props" do
      %{tree: tree} = render_page(Module152, %{name: "ada"}, @server, initial_page?: true)

      assert print_dom(tree) ==
               ~s'layout vars = %{cid: &quot;layout&quot;, prop_1: &quot;ada!&quot;, prop_3: &quot;ADA&quot;}'
    end

    test "holds the derived fields in the page struct, emptied for the client" do
      result = render_page(Module152, %{name: "ada"}, @server, initial_page?: true)

      assert result.component_registry["page"].struct.derived == %{prop_1: "ada!", prop_3: "ADA"}
      assert result.mount_data.component_registry["page"].struct.derived == %{}
    end
  end
end
