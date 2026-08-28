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
  alias Hologram.Test.Fixtures.Template.Renderer.Module103
  alias Hologram.Test.Fixtures.Template.Renderer.Module105
  alias Hologram.Test.Fixtures.Template.Renderer.Module106
  alias Hologram.Test.Fixtures.Template.Renderer.Module107
  alias Hologram.Test.Fixtures.Template.Renderer.Module108
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

    dump_query_cache(QueryCacheStub, [Module97, Module105, Module106, Module108, Module95])

    QueryCache.init(nil)

    :ok
  end

  @env %Renderer.Env{}

  @entity_2_type "Hologram.Test.Fixtures.Entity.Module2"
  @role_grant_type "Hologram.Auth.RoleGrant"
  @page_opts [
    csrf_token: "test-csrf-token",
    initial_page?: true,
    instance_id: "instance-1",
    replica_id: "test-replica-id",
    replica_token: "test-replica-token"
  ]
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

  test "injects a parameterized from_query prop bound to a like-named prop" do
    create_entities()

    node = {:component, Module105, [{"min_b", [expression: {5}]}], []}

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

    node = {:component, Module106, [], []}

    expected_msg =
      "from_query for prop :entities in Hologram.Test.Fixtures.Template.Renderer.Module106 binds argument :missing_prop - no like-named prop is set"

    assert_error ArgumentError, expected_msg, fn ->
      render_dom(node, @env, @server)
    end
  end

  test "injects a from_query prop row with its server-only attributes already replaced by the sentinel" do
    {:ok, _entity} =
      %{label: "Report", secret_note: "note_secret_v7", token: "tok_R4mQ"}
      |> Module15.new()
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

      ETS.put(PageDigestRegistryStub.ets_table_name(), Module107, :dummy_module_107_digest)

      public_entity =
        %{priority: 1, public: true}
        |> PolicyEntity.new()
        |> DB.create!()

      private_entity =
        %{priority: 2, public: false}
        |> PolicyEntity.new()
        |> DB.create!()

      {:ok, private_entity: private_entity, public_entity: public_entity}
    end

    test "renders only the rows the session user's policy grants", %{
      private_entity: private_entity
    } do
      user =
        %{email: "renderer_1@example.com"}
        |> Module14.new()
        |> DB.create!()

      Auth.grant_role(user, private_entity, :viewer)

      html = render_page_html(Module107, %Server{user_id: user.id})

      assert String.contains?(html, "entities = 1,2")
    end

    test "renders only unconditionally visible rows for an anonymous session" do
      html = render_page_html(Module107)

      assert String.contains?(html, "entities = 1")
      refute String.contains?(html, "entities = 1,2")
    end
  end

  describe "the rows a page hands its client" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_asset_manifest_cache(AssetManifestCacheStub)
      setup_page_digest_registry(PageDigestRegistryStub)

      ETS.put(PageDigestRegistryStub.ets_table_name(), Module99, :dummy_module_99_digest)
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module100, :dummy_module_100_digest)
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module102, :dummy_module_102_digest)

      dump_query_cache(QueryCacheStub, [Module98, Module95, Module101])
      QueryCache.init(nil)

      :ok
    end

    # What the page carries, apart from what it renders - a template that prints the sentinel
    # names a server-only attribute legitimately, and the question here is what the data layer
    # was handed.
    defp carried_rows_json(html) do
      [_full, json] = Regex.run(~r/syncRows: (.+)$/m, html)

      json
    end

    # The document the HTML path serves: the tree with its mount data put back, printed. The
    # renderer hands the two out separately, because the navigation path carries them separately.
    defp render_page_html(page_module, server_struct \\ %Server{}, params \\ %{}) do
      %{mount_data: mount_data, tree: tree} =
        render_page(page_module, params, server_struct, @page_opts)

      tree
      |> interpolate_js_in_tree(mount_replacements(mount_data))
      |> print_dom()
    end

    # The rows travel flat, each once, with the to-many naming the ids it holds - the shape a
    # frame carries, read on the client by the same ingest.
    test "carries the rows its props read, embedded rows among them" do
      {:ok, required} = create(Module1.new())

      {:ok, target} =
        %{a: true, c: "the embedded row"}
        |> Entity2.new()
        |> create()

      {:ok, source} =
        %{c_id: required.id}
        |> Module3.new()
        |> create()

      :ok = add_relationship(Module3, source.id, :a, target.id)

      html = render_page_html(Module99)

      assert String.contains?(html, ~s|syncRows: {"put_entity":{|)
      assert String.contains?(html, ~s|"#{@entity_2_type}":[{|)
      assert String.contains?(html, ~s|"c":"the embedded row"|)
      assert String.contains?(html, ~s|"a":["#{target.id}"]|)
    end

    # A row holds whatever was written to the database, and it is printed into a script element -
    # so a value that spells a closing tag would end that element and put whatever follows it into
    # the document as markup. The escape leaves the value identical to whoever parses the JSON.
    test "carries a value that spells a closing tag without ending the script" do
      {:ok, required} = create(Module1.new())

      {:ok, target} =
        %{a: true, c: "</script><script>alert(1)</script>"}
        |> Entity2.new()
        |> create()

      {:ok, source} =
        %{c_id: required.id}
        |> Module3.new()
        |> create()

      :ok = add_relationship(Module3, source.id, :a, target.id)

      carried = carried_rows_json(render_page_html(Module99))

      refute String.contains?(carried, "</script>")

      assert String.contains?(
               carried,
               ~S|"c":"\u003C\/script>\u003Cscript>alert(1)\u003C\/script>"|
             )
    end

    test "carries nothing for a page whose props read no rows" do
      html = render_page_html(Module99)

      assert String.contains?(html, "syncRows: {}")
    end

    # The positive artifact beside the negative one: this is what the row travelled in, so
    # what it does not carry is what the model kept from it rather than what happened to be
    # missing.
    test "never carries a value the client may not have" do
      {:ok, _entity} =
        %{label: "Report", secret_note: "note_secret_v7", token: "tok_R4mQ"}
        |> Module15.new()
        |> create()

      carried = carried_rows_json(render_page_html(Module100))

      assert String.contains?(carried, ~s|"label":"Report"|)
      refute String.contains?(carried, "note_secret_v7")
      refute String.contains?(carried, "secret_note")
      refute String.contains?(carried, "tok_R4mQ")
      refute String.contains?(carried, "token")
    end

    test "names who the render read the rows as" do
      user =
        %{email: "seeded@example.com"}
        |> Module14.new()
        |> DB.create!()

      html = render_page_html(Module99, %Server{user_id: user.id})

      assert String.contains?(html, ~s|actorUserId: "#{user.id}"|)
    end

    test "names nobody for a visitor" do
      html = render_page_html(Module99)

      assert String.contains?(html, "actorUserId: null")
    end
  end

  # A count has no rows behind it, so carried rows cannot re-derive one - the number itself
  # travels, keyed by the prop instance that answered it.
  describe "the counts a page hands its client" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_asset_manifest_cache(AssetManifestCacheStub)
      setup_page_digest_registry(PageDigestRegistryStub)

      ETS.put(PageDigestRegistryStub.ets_table_name(), Module99, :dummy_module_99_digest)
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module102, :dummy_module_102_digest)

      dump_query_cache(QueryCacheStub, [Module101, Module98])
      QueryCache.init(nil)

      :ok
    end

    # The trailing comma and the line ending belong to the script around the value rather than to
    # the value - and the line ending is not always one character, since a checkout on Windows
    # carries CRLF into the template the script is written in.
    defp carried_counts_json(html) do
      [_full, json] = Regex.run(~r/syncCounts: (.+)$/m, html)

      json
      |> String.trim()
      |> String.trim_trailing(",")
    end

    defp render_counts_page_html do
      html = render_page_html(Module102)

      html
    end

    # Read back through a JSON decoder rather than matched as a substring: the counts are printed
    # into a script element, so their spelling carries escapes an HTML parser must not read as
    # markup - and what this test is about is the counts, not how they are spelled.
    test "carries the count each instance of a count prop answered" do
      create_entities()

      counts =
        render_counts_page_html()
        |> carried_counts_json()
        |> Jason.decode!()

      assert counts == %{
               "#{inspect(Module101)}/total/false" => 1,
               "#{inspect(Module101)}/total/true" => 2
             }
    end

    test "carries nothing for a page whose props count nothing" do
      html = render_page_html(Module99)

      assert String.contains?(html, "syncCounts: {}")
    end
  end

  # A permission check reads no rows - it asks whether a grant exists - so the rows behind its
  # answer are looked up once the render's questions are all in, and carried like any others.
  # Without them the client's first render would deny what the server just allowed.
  describe "the grants a page hands its client" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_asset_manifest_cache(AssetManifestCacheStub)
      setup_page_digest_registry(PageDigestRegistryStub)

      ETS.put(PageDigestRegistryStub.ets_table_name(), Module103, :dummy_module_103_digest)

      dump_query_cache(QueryCacheStub, [])
      QueryCache.init(nil)

      :ok
    end

    defp render_grants_page_html(entity_id, server_struct) do
      html =
        render_page_html(Module103, server_struct, %{entity_id: entity_id})

      html
    end

    test "carries the row answering a check the render ran" do
      {:ok, user} =
        %{email: "renderer_grants_1@example.com"}
        |> Module14.new()
        |> create()

      {:ok, entity} =
        %{priority: 5}
        |> PolicyEntity.new()
        |> create()

      Auth.grant_role(user, entity, :viewer)

      html = render_grants_page_html(entity.id, %Server{user_id: user.id})

      assert String.contains?(html, "may read = true")
      assert String.contains?(html, ~s|"#{@role_grant_type}":[{|)
      assert String.contains?(html, ~s|"user_id":"#{user.id}"|)
    end

    test "carries no grant row for a check nothing answers" do
      {:ok, user} =
        %{email: "renderer_grants_2@example.com"}
        |> Module14.new()
        |> create()

      {:ok, entity} =
        %{priority: 5}
        |> PolicyEntity.new()
        |> create()

      html = render_grants_page_html(entity.id, %Server{user_id: user.id})

      assert String.contains?(html, "may read = false")
      refute String.contains?(html, @role_grant_type)
    end

    test "carries no grant row for an anonymous session" do
      {:ok, entity} =
        %{priority: 5}
        |> PolicyEntity.new()
        |> create()

      html = render_grants_page_html(entity.id, %Server{})

      assert String.contains?(html, "may read = false")
      refute String.contains?(html, @role_grant_type)
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
        %{email: "renderer_2@example.com"}
        |> Module14.new()
        |> DB.create!()

      html = render_page_html(Module93, %Server{user_id: user.id})

      assert String.contains?(html, "current user = renderer_2@example.com")
    end

    test "hands over the row with its server-only attributes already replaced by the sentinel" do
      user =
        %{email: "renderer_5@example.com", password_hash: "hash_9dTf"}
        |> Module14.new()
        |> DB.create!()

      %{component_registry: component_registry} =
        render_page(Module93, %{}, %Server{user_id: user.id}, @page_opts)

      context_user = component_registry["page"].struct.emitted_context[{Hologram, :user}]

      assert context_user.password_hash == %ServerOnly{attribute: :password_hash}
      assert context_user.email == "renderer_5@example.com"
    end

    test "exposes nil for an anonymous session" do
      html = render_page_html(Module93)

      assert String.contains?(html, "current user = none")
    end

    test "exposes nil when no row carries the session user id" do
      dangling_user_id = Entity.generate_id()

      html = render_page_html(Module93, %Server{user_id: dangling_user_id})

      assert String.contains?(html, "current user = none")
    end

    test "exposes nil for a session user id that is not a canonical entity id" do
      html = render_page_html(Module93, %Server{user_id: 7})

      assert String.contains?(html, "current user = none")
    end
  end
end
