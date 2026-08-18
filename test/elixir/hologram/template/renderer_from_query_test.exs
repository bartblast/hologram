defmodule Hologram.Template.RendererFromQueryTest do
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.DB.EntityOperations, only: [add_relationship: 4, create: 1]
  import Hologram.Template.Renderer
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Auth
  alias Hologram.Commons.ETS
  alias Hologram.DB
  alias Hologram.DB.QueryCache
  alias Hologram.Entity
  alias Hologram.Entity.ServerOnly
  alias Hologram.Server
  alias Hologram.Template.Renderer
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyEntity
  alias Hologram.Test.Fixtures.Template.Renderer.Module100
  alias Hologram.Test.Fixtures.Template.Renderer.Module101
  alias Hologram.Test.Fixtures.Template.Renderer.Module102
  alias Hologram.Test.Fixtures.Template.Renderer.Module89
  alias Hologram.Test.Fixtures.Template.Renderer.Module90
  alias Hologram.Test.Fixtures.Template.Renderer.Module91
  alias Hologram.Test.Fixtures.Template.Renderer.Module92
  alias Hologram.Test.Fixtures.Template.Renderer.Module93
  alias Hologram.Test.Fixtures.Template.Renderer.Module95
  alias Hologram.Test.Fixtures.Template.Renderer.Module97
  alias Hologram.Test.Fixtures.Template.Renderer.Module98
  alias Hologram.Test.Fixtures.Template.Renderer.Module99

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry
  use_module_stub :query_cache

  setup :set_mox_global

  setup do
    setup_query_cache(QueryCacheStub, false)

    stub(QueryCacheMock, :component_modules, fn ->
      [Module97, Module89, Module90, Module92, Module95]
    end)

    QueryCache.init(nil)

    :ok
  end

  @env %Renderer.Env{}

  @entity_2_type "Hologram.Test.Fixtures.Entity.Module2"
  @page_opts [csrf_token: "test-csrf-token", initial_page?: true, instance_id: "instance-1"]
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

    node = {:component, Module97, [], []}

    assert {"entities = banana,cherry", %{}, @server} = render_dom(node, @env, @server)
  end

  test "rejects template values for from_query props" do
    create_entities()

    node = {:component, Module97, [{"entities", [expression: {[:template_value]}]}], []}

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

  test "injects a from_query prop row with its server-only attributes already replaced by the sentinel" do
    Module15
    |> Entity.new(label: "Report", secret_note: "note_secret_v7", token: "tok_R4mQ")
    |> create()

    node = {:component, Module95, [], []}

    {html, _component_registry, _server_struct} = render_dom(node, @env, @server)

    assert String.contains?(html, "labels = Report")

    assert String.contains?(
             html,
             "secret_note = %Hologram.Entity.ServerOnly{attribute: :secret_note}"
           )

    assert String.contains?(html, "token = %Hologram.Entity.ServerOnly{attribute: :token}")
    refute String.contains?(html, "note_secret_v7")
    refute String.contains?(html, "tok_R4mQ")
  end

  describe "policy filtering" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_asset_manifest_cache(AssetManifestCacheStub)
      setup_page_digest_registry(PageDigestRegistryStub)

      ETS.put(PageDigestRegistryStub.ets_table_name(), Module91, :dummy_module_91_digest)

      public_entity =
        PolicyEntity
        |> Entity.new(priority: 1, public: true)
        |> DB.create()

      private_entity =
        PolicyEntity
        |> Entity.new(priority: 2, public: false)
        |> DB.create()

      {:ok, private_entity: private_entity, public_entity: public_entity}
    end

    test "renders only the rows the session user's policy grants", %{
      private_entity: private_entity
    } do
      user =
        Module14
        |> Entity.new(email: "renderer_1@example.com")
        |> DB.create()

      Auth.grant_role(user, private_entity, :viewer)

      {html, _tree, _component_registry, _server_struct} =
        render_page(Module91, %{}, %Server{user_id: user.id}, @page_opts)

      assert String.contains?(html, "entities = 1,2")
    end

    test "renders only unconditionally visible rows for an anonymous session" do
      {html, _tree, _component_registry, _server_struct} =
        render_page(Module91, %{}, %Server{}, @page_opts)

      assert String.contains?(html, "entities = 1")
      refute String.contains?(html, "entities = 1,2")
    end
  end

  describe "the seed a page hands its client" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_asset_manifest_cache(AssetManifestCacheStub)
      setup_page_digest_registry(PageDigestRegistryStub)

      ETS.put(PageDigestRegistryStub.ets_table_name(), Module99, :dummy_module_99_digest)
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module100, :dummy_module_100_digest)
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module102, :dummy_module_102_digest)

      stub(QueryCacheMock, :component_modules, fn -> [Module98, Module95, Module101] end)
      QueryCache.init(nil)

      :ok
    end

    # What the seed carries, apart from what the page around it renders - a template that prints
    # the sentinel names a server-only attribute legitimately, and the question here is what the
    # data layer was handed.
    defp seed_json(html) do
      [_full, json] = Regex.run(~r/syncSeed: (.+)$/m, html)

      json
    end

    defp render_page_html(page_module, server_struct \\ %Server{}) do
      {html, _tree, _component_registry, _final_server_struct} =
        render_page(page_module, %{}, server_struct, @page_opts)

      html
    end

    # The rows travel flat, each once, with the to-many naming the ids it holds - the shape a
    # frame carries, read on the client by the same ingest.
    test "carries the rows its props read, embedded rows among them" do
      required =
        Module1
        |> Entity.new()
        |> create()

      target =
        Entity2
        |> Entity.new(a: true, c: "the embedded row")
        |> create()

      source =
        Module3
        |> Entity.new(c_id: required.id)
        |> create()

      :ok = add_relationship(Module3, source.id, :a, target.id)

      html = render_page_html(Module99)

      assert String.contains?(html, ~s|syncSeed: {"put_entity":{|)
      assert String.contains?(html, ~s|"#{@entity_2_type}":[{|)
      assert String.contains?(html, ~s|"c":"the embedded row"|)
      assert String.contains?(html, ~s|"a":["#{target.id}"]|)
    end

    test "carries nothing for a page whose props read no rows" do
      html = render_page_html(Module99)

      assert String.contains?(html, "syncSeed: {}")
    end

    # The positive artifact beside the negative one: this is the seed the row travelled in, so
    # what it does not carry is what the model kept from it rather than what happened to be
    # missing.
    test "never carries a value the client may not have" do
      Module15
      |> Entity.new(label: "Report", secret_note: "note_secret_v7", token: "tok_R4mQ")
      |> create()

      seed = seed_json(render_page_html(Module100))

      assert String.contains?(seed, ~s|"label":"Report"|)
      refute String.contains?(seed, "note_secret_v7")
      refute String.contains?(seed, "secret_note")
      refute String.contains?(seed, "tok_R4mQ")
      refute String.contains?(seed, "token")
    end

    test "names who the render read the rows as" do
      user =
        Module14
        |> Entity.new(email: "seeded@example.com")
        |> DB.create()

      html = render_page_html(Module99, %Server{user_id: user.id})

      assert String.contains?(html, ~s|actorUserId: "#{user.id}"|)
    end

    test "names nobody for a visitor" do
      html = render_page_html(Module99)

      assert String.contains?(html, "actorUserId: null")
    end
  end

  # A count has no rows behind it, so a seeded pot cannot re-derive one - the number itself
  # travels, keyed by the prop instance that answered it.
  describe "the counts a page hands its client" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_asset_manifest_cache(AssetManifestCacheStub)
      setup_page_digest_registry(PageDigestRegistryStub)

      ETS.put(PageDigestRegistryStub.ets_table_name(), Module99, :dummy_module_99_digest)
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module102, :dummy_module_102_digest)

      stub(QueryCacheMock, :component_modules, fn -> [Module101, Module98] end)
      QueryCache.init(nil)

      :ok
    end

    defp render_counts_page_html do
      {html, _tree, _component_registry, _final_server_struct} =
        render_page(Module102, %{}, %Server{}, @page_opts)

      html
    end

    test "carries the count each instance of a count prop answered" do
      create_entities()

      html = render_counts_page_html()

      assert String.contains?(
               html,
               ~s|syncCounts: {"#{inspect(Module101)}/total/false":1,"#{inspect(Module101)}/total/true":2}|
             )
    end

    test "carries nothing for a page whose props count nothing" do
      html = render_page_html(Module99)

      assert String.contains?(html, "syncCounts: {}")
    end
  end

  describe "current-user context" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_asset_manifest_cache(AssetManifestCacheStub)
      setup_page_digest_registry(PageDigestRegistryStub)

      ETS.put(PageDigestRegistryStub.ets_table_name(), Module93, :dummy_module_93_digest)

      :ok
    end

    test "exposes the session user's row to a from_context prop" do
      user =
        Module14
        |> Entity.new(email: "renderer_2@example.com")
        |> DB.create()

      {html, _tree, _component_registry, _server_struct} =
        render_page(Module93, %{}, %Server{user_id: user.id}, @page_opts)

      assert String.contains?(html, "current user = renderer_2@example.com")
    end

    test "hands over the row with its server-only attributes already replaced by the sentinel" do
      user =
        Module14
        |> Entity.new(email: "renderer_5@example.com", password_hash: "hash_9dTf")
        |> DB.create()

      {_html, _tree, component_registry, _server_struct} =
        render_page(Module93, %{}, %Server{user_id: user.id}, @page_opts)

      context_user = component_registry["page"].struct.emitted_context[{Hologram, :user}]

      assert context_user.password_hash == %ServerOnly{attribute: :password_hash}
      assert context_user.email == "renderer_5@example.com"
    end

    test "exposes nil for an anonymous session" do
      {html, _tree, _component_registry, _server_struct} =
        render_page(Module93, %{}, %Server{}, @page_opts)

      assert String.contains?(html, "current user = none")
    end

    test "exposes nil when no row carries the session user id" do
      dangling_user_id = Entity.generate_id()

      {html, _tree, _component_registry, _server_struct} =
        render_page(Module93, %{}, %Server{user_id: dangling_user_id}, @page_opts)

      assert String.contains?(html, "current user = none")
    end

    test "exposes nil for a session user id that is not a canonical entity id" do
      {html, _tree, _component_registry, _server_struct} =
        render_page(Module93, %{}, %Server{user_id: 7}, @page_opts)

      assert String.contains?(html, "current user = none")
    end
  end
end
