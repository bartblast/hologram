defmodule Hologram.Template.RendererDerivedTest do
  # async: false - the tests write the query cache's persistent term (QueryCache.init/1) and
  # restart the asset path registry under its registered name, both shared by the whole node.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.DB.EntityOperations, only: [add_relationship: 4, create: 1]
  import Hologram.Template.Renderer
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Auth
  alias Hologram.Auth.Context
  alias Hologram.Commons.ETS
  alias Hologram.Controller
  alias Hologram.DB
  alias Hologram.DB.QueryCache
  alias Hologram.Entity
  alias Hologram.Entity.NotIncluded
  alias Hologram.Entity.ServerOnly
  alias Hologram.Policy
  alias Hologram.Server
  alias Hologram.Sync.Carry
  alias Hologram.Template.Renderer
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Entity.Module25
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module28
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module32
  alias Hologram.Test.Fixtures.Entity.Module33
  alias Hologram.Test.Fixtures.Entity.Module37
  alias Hologram.Test.Fixtures.Entity.Module38
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyEntity
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyParent
  alias Hologram.Test.Fixtures.Policy.Module33, as: PolicyVault
  alias Hologram.Test.Fixtures.Policy.Module34, as: PolicyKey
  alias Hologram.Test.Fixtures.Policy.Module5, as: PolicyMiddle
  alias Hologram.Test.Fixtures.Policy.Module8, as: PolicyChained
  alias Hologram.Test.Fixtures.Template.Renderer.Module126
  alias Hologram.Test.Fixtures.Template.Renderer.Module131
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
  alias Hologram.Test.Fixtures.Template.Renderer.Module161
  alias Hologram.Test.Fixtures.Template.Renderer.Module162
  alias Hologram.Test.Fixtures.Template.Renderer.Module163
  alias Hologram.Test.Fixtures.Template.Renderer.Module164
  alias Hologram.Test.Fixtures.Template.Renderer.Module165
  alias Hologram.Test.Fixtures.Template.Renderer.Module166
  alias Hologram.Test.Fixtures.Template.Renderer.Module167
  alias Hologram.Test.Fixtures.Template.Renderer.Module168
  alias Hologram.Test.Fixtures.Template.Renderer.Module169
  alias Hologram.Test.Fixtures.Template.Renderer.Module170
  alias Hologram.Test.Fixtures.Template.Renderer.Module171
  alias Hologram.Test.Fixtures.Template.Renderer.Module172
  alias Hologram.Test.Fixtures.Template.Renderer.Module173
  alias Hologram.Test.Fixtures.Template.Renderer.Module174
  alias Hologram.Test.Fixtures.Template.Renderer.Module175

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :chunk_registry
  use_module_stub :page_digest_registry
  use_module_stub :query_cache

  setup :set_mox_global

  setup do
    setup_chunk_registry(ChunkRegistryStub)
    setup_query_cache(QueryCacheStub, false)

    dump_query_cache(QueryCacheStub, [
      Module149,
      Module150,
      Module151,
      Module157,
      Module158,
      Module161,
      Module162,
      Module170,
      Module171
    ])

    QueryCache.init(nil)

    :ok
  end

  @entity_2_type "Hologram.Test.Fixtures.Entity.Module2"
  @env %Renderer.Env{}
  @page_opts [
    csrf_token: "test-csrf-token",
    initial_page?: true,
    instance_id: "instance-1",
    replica_id: "test-replica-id",
    replica_token: "test-replica-token"
  ]
  @role_grant_type "Hologram.Auth.RoleGrant"
  @server %Server{}

  # The boot data block of a printed document, decoded.
  defp boot_data(html) do
    [_full, json] =
      Regex.run(~r'<script[^>]* id="hologram-boot-data"[^>]*>(.*?)</script>'s, html)

    Jason.decode!(json)
  end

  # The document the HTML path serves: the tree printed with its boot data block filled in, the way
  # the controller fills it.
  defp render_page_html(page_module, server_struct \\ %Server{}, params \\ %{}) do
    result = render_page(page_module, params, server_struct, @page_opts)

    boot_data =
      Controller.build_boot_data(%{
        chunk_digests: result.chunk_digests,
        csrf_token: @page_opts[:csrf_token],
        identity_tag: "test-identity-tag",
        instance_id: @page_opts[:instance_id],
        mount_data: result.mount_data,
        page_digest: PageDigestRegistry.lookup(page_module),
        replica_id: @page_opts[:replica_id],
        replica_token: @page_opts[:replica_token],
        self_echoes: [],
        sub_receipt_adds: [],
        sub_receipt_drops: []
      })

    print_dom(result.tree, fills: %{"boot_data" => boot_data_element(boot_data, nil)})
  end

  defp setup_page_rendering(page_digests) do
    setup_asset_path_registry(AssetPathRegistryStub)
    AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

    setup_asset_manifest_cache(AssetManifestCacheStub)
    setup_page_digest_registry(PageDigestRegistryStub)

    Enum.each(page_digests, fn {page_module, digest} ->
      ETS.put(PageDigestRegistryStub.ets_table_name(), page_module, digest)
    end)
  end

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

    test "computes a field over a value the template passes under its name" do
      create_entities()

      node = {:component, Module149, [{"entities", [expression: {[:template_value]}]}], []}

      assert render_dom(node, @env, @server) == {"entities = banana,cherry", %{}, @server}
    end

    test "renders the rows a field's query reads with the props its function names" do
      create_entities()

      node = {:component, Module161, [{"min_b", [expression: {5}]}], []}

      assert render_dom(node, @env, @server) == {"entities = cherry", %{}, @server}
    end

    test "hands the template a row with its server-only attributes already replaced by the sentinel" do
      {:ok, _entity} =
        %{label: "Report", secret_note: "note_secret_v7", token: "tok_R4mQ"}
        |> Module15.new()
        |> create()

      {html, _component_registry, _server_struct} =
        render_dom({:component, Module162, [], []}, @env, @server)

      assert String.contains?(html, "labels = Report")

      assert String.contains?(
               html,
               "secret_note = %Hologram.Entity.ServerOnly{attribute: :secret_note}"
             )

      assert String.contains?(html, "token = %Hologram.Entity.ServerOnly{attribute: :token}")
      refute String.contains?(html, "note_secret_v7")
      refute String.contains?(html, "tok_R4mQ")
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

    test "carries a count reading another field's rows under those rows" do
      create_entities()

      Carry.start()

      {_html, component_registry, _server_struct} =
        render_dom(stateful_node(Module151), @env, @server)

      ripe = component_registry["my_component"].struct.derived.ripe
      spelled_rows = Enum.map_join(ripe, ", ", &"#{inspect(Entity2)}##{&1.id}")

      assert Carry.take_counts() == %{"#{inspect(Module151)}/ripe_total/[#{spelled_rows}]" => 2}
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

  describe "derived includes" do
    # The window of an include of derived fields is built from their definitions, which the
    # compile resolves before the queries are registered.
    setup do
      put_derived_definitions([Module32, Module37, Module38])

      dump_query_cache(QueryCacheStub, [Module164])
      QueryCache.init(nil)

      :ok
    end

    # The window reads the rows a derived field is computed from beside the rows the query returns,
    # and the template is handed the derived values without them.
    test "hands the template the derived fields the query included" do
      {:ok, channel} = create(Module32.new(name: "general"))

      for position <- [1, 2, 3] do
        {:ok, _message} =
          %{body: "message #{position}", channel_id: channel.id, position: position}
          |> Module33.new()
          |> create()
      end

      {html, _component_registry, _server_struct} =
        render_dom({:component, Module164, [], []}, @env, @server)

      not_included = inspect(%NotIncluded{relationship: :messages})

      assert String.contains?(html, "counts = 3")
      assert String.contains?(html, "recent = 3-2")
      assert String.contains?(html, "messages = #{not_included}")
    end

    # The template is handed a derived set's rows with the author their definition includes - read
    # under the author type's read policy, which lets nobody read one, so nil rather than the
    # sentinel - and not the messages the window embeds to compute them.
    test "hands the template a derived set's rows with what its definition includes" do
      {:ok, room} = create(Module37.new(name: "general"))
      {:ok, author} = create(Module1.new())

      {:ok, _message} =
        %{author_id: author.id, channel_id: room.id, pinned: false}
        |> Module38.new()
        |> create()

      {html, _component_registry, _server_struct} =
        render_dom({:component, Module164, [], []}, @env, @server)

      not_included = inspect(%NotIncluded{relationship: :messages})

      assert String.contains?(html, "authors = nil")
      assert String.contains?(html, "room messages = #{not_included}")
    end
  end

  describe "policy filtering on a page" do
    setup do
      setup_page_rendering([{Module165, :dummy_module_165_digest}])

      %{priority: 1, public: true}
      |> PolicyEntity.new()
      |> DB.create!()

      private_entity =
        %{priority: 2, public: false}
        |> PolicyEntity.new()
        |> DB.create!()

      {:ok, private_entity: private_entity}
    end

    test "renders only the rows the session user's policy grants", %{
      private_entity: private_entity
    } do
      user =
        %{email: "renderer_derived_2@example.com"}
        |> Module14.new()
        |> DB.create!()

      Auth.grant_role(user, :viewer, private_entity)

      html = render_page_html(Module165, %Server{user_id: user.id})

      assert String.contains?(html, "entities = 1,2")
    end

    test "renders only unconditionally visible rows for an anonymous session" do
      html = render_page_html(Module165)

      assert String.contains?(html, "entities = 1")
      refute String.contains?(html, "entities = 1,2")
    end
  end

  describe "the rows a page hands its client" do
    setup do
      setup_page_rendering([
        {Module163, :dummy_module_163_digest},
        {Module167, :dummy_module_167_digest}
      ])

      dump_query_cache(QueryCacheStub, [Module162, Module166])
      QueryCache.init(nil)

      :ok
    end

    # What the page carries, apart from what it renders - a template that prints the sentinel
    # names a server-only attribute legitimately, and the question here is what the data layer
    # was handed.
    defp carried_rows_json(html) do
      Jason.encode!(boot_data(html)["syncRows"])
    end

    # The rows travel flat, each once, with the to-many naming the ids it holds - the shape a
    # frame carries, read on the client by the same ingest.
    test "carries the rows its fields read, embedded rows among them" do
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

      html = render_page_html(Module167)

      assert String.contains?(html, ~s|"syncRows":{"put_entity":{|)
      assert String.contains?(html, ~s|"#{@entity_2_type}":[{|)
      assert String.contains?(html, ~s|"c":"the embedded row"|)
      assert String.contains?(html, ~s|"a":["#{target.id}"]|)
    end

    # A row holds whatever was written to the database, and it is printed into the boot data block -
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

      html = render_page_html(Module167)

      refute String.contains?(html, "</script><script>alert(1)")
      assert String.contains?(html, ~S|"c":"\u003C/script>\u003Cscript>alert(1)\u003C/script>"|)
    end

    test "carries nothing for a page whose fields read no rows" do
      html = render_page_html(Module167)

      assert String.contains?(html, ~s|"syncRows":{}|)
    end

    # The positive artifact beside the negative one: this is what the row travelled in, so
    # what it does not carry is what the model kept from it rather than what happened to be
    # missing.
    test "never carries a value the client may not have" do
      {:ok, _entity} =
        %{label: "Report", secret_note: "note_secret_v7", token: "tok_R4mQ"}
        |> Module15.new()
        |> create()

      carried = carried_rows_json(render_page_html(Module163))

      assert String.contains?(carried, ~s|"label":"Report"|)
      refute String.contains?(carried, "note_secret_v7")
      refute String.contains?(carried, "secret_note")
      refute String.contains?(carried, "tok_R4mQ")
      refute String.contains?(carried, "token")
    end

    # The server works a carried row's verdicts out over the row as stored, its server-only values
    # among them - the wire then leaves those out of what the client is told.
    test "carries a row's verdicts worked out over its server-only values" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module169, :dummy_module_169_digest)
      dump_query_cache(QueryCacheStub, [Module168], true)
      QueryCache.init(nil)

      vault =
        %{code: "kestrel", public: true}
        |> PolicyVault.new()
        |> DB.create!()

      %{name: "kestrel", vault_id: vault.id}
      |> PolicyKey.new()
      |> DB.create!()

      [{verdict_key, _clause}] = Policy.deciding_quantifiers(PolicyVault)

      assert [carried] =
               Module169
               |> render_page_html()
               |> boot_data()
               |> get_in(["syncRows", "put_entity", inspect(PolicyVault)])

      assert carried["$verdicts"] == %{verdict_key => false}
      refute Map.has_key?(carried, "code")
    end

    test "names who the render read the rows as" do
      user =
        %{email: "seeded@example.com"}
        |> Module14.new()
        |> DB.create!()

      html = render_page_html(Module167, %Server{user_id: user.id})

      assert String.contains?(html, ~s|"actorUserId":"#{user.id}"|)
    end

    test "names nobody for a visitor" do
      html = render_page_html(Module167)

      assert String.contains?(html, ~s|"actorUserId":null|)
    end
  end

  describe "the rows a query's paths read" do
    # One row reaches a public row, one a row nobody signed out may read, one nothing - the path
    # reads the first as a value and the other two as missing.
    setup do
      {:ok, required} =
        %{a: ~D[2026-01-01], b: ~U[2026-01-01 00:00:00.000000Z], c: :x, d: 1.5}
        |> Module4.new()
        |> create()

      {:ok, shown} =
        %{public: true, title: "shown"}
        |> Module13.new()
        |> create()

      {:ok, hidden} =
        %{public: false, title: "hidden"}
        |> Module13.new()
        |> create()

      Enum.each([shown.id, hidden.id, nil], fn h_id ->
        {:ok, _entity} =
          %{f_id: required.id, h_id: h_id}
          |> Module25.new()
          |> create()
      end)

      Carry.start()

      :ok
    end

    defp carried_titles do
      %{put_entity: rows} = Carry.take(nil)

      rows
      |> Map.get("Hologram.Test.Fixtures.Entity.Module13", [])
      |> Enum.map(& &1.title)
    end

    # The client answers the query over the rows it holds, so the row a path reads is handed over
    # beside the rows the query returns - the one the session may read, and no other.
    test "carries the rows a path reads that the session may read" do
      render_dom({:component, Module158, [], []}, @env, @server)

      assert carried_titles() == ["shown"]
    end

    test "hands the template no relationship the query did not include" do
      not_included = inspect(%NotIncluded{relationship: :h})

      assert render_dom({:component, Module158, [], []}, @env, @server) ==
               {"h = #{not_included},#{not_included},#{not_included}", %{}, @server}
    end

    test "hands the template a relationship the query included through a path" do
      {html, _component_registry, _server_struct} =
        render_dom({:component, Module170, [], []}, @env, @server)

      assert String.contains?(html, "titles = shown,,")
      assert carried_titles() == ["shown"]
    end

    # A path inside a quantifier over an inverse reads its rows' relationships too - and the template
    # is handed the included inverse's rows as the query asked for them, without what the path read.
    test "hands the template no relationship of an inverse's rows the query did not include" do
      {:ok, channel} =
        %{name: "general"}
        |> Module26.new()
        |> create()

      {:ok, _message} =
        %{body: "hi", channel_id: channel.id, position: 1}
        |> Module28.new()
        |> create()

      {html, _component_registry, _server_struct} =
        render_dom({:component, Module171, [], []}, @env, @server)

      not_included = inspect(%NotIncluded{relationship: :channel})

      assert String.contains?(html, "channel = #{not_included}")
    end
  end

  # A client checking permissions answers each rule over the rows it holds, so a render reads the
  # rows the queried types' rules read through relationships and hands them over with the rows the
  # queries return - under the session user's own read rules.
  describe "the rows a query's rules read" do
    setup do
      setup_page_rendering([{Module173, :dummy_module_173_digest}])

      dump_query_cache(QueryCacheStub, [Module172], true)
      QueryCache.init(nil)

      :ok
    end

    defp carried_ids(html, type) do
      html
      |> boot_data()
      |> get_in(["syncRows", "put_entity", inspect(type)])
      |> List.wrap()
      |> Enum.map(& &1["id"])
    end

    # Two public rows, each delegating its publish rule to a parent of its own, and a user who may
    # read only the first parent.
    defp create_parented_entities do
      {:ok, user} =
        %{email: "renderer_rules_#{System.unique_integer([:positive])}@example.com"}
        |> Module14.new()
        |> create()

      {:ok, readable_parent} = create(PolicyParent.new())
      {:ok, unreadable_parent} = create(PolicyParent.new())

      Auth.grant_role(user, :member, readable_parent)

      Enum.each([{1, readable_parent}, {2, unreadable_parent}], fn {priority, parent} ->
        {:ok, _entity} =
          %{parent_id: parent.id, priority: priority, public: true}
          |> PolicyEntity.new()
          |> create()
      end)

      %{readable_parent: readable_parent, user: user}
    end

    test "carries the rows the rules read that the session may read" do
      %{readable_parent: readable_parent, user: user} = create_parented_entities()

      html = render_page_html(Module173, %Server{user_id: user.id})

      assert carried_ids(html, PolicyParent) == [readable_parent.id]
    end

    # The row two relationships away is not public, so no query returns it - it arrives for the
    # rule alone, read through the viewer's grant.
    test "carries the rows along a delegation chain two rows long" do
      {:ok, user} =
        %{email: "renderer_rules_chain@example.com"}
        |> Module14.new()
        |> create()

      {:ok, top} = create(PolicyEntity.new())

      Auth.grant_role(user, :viewer, top)

      {:ok, middle} =
        %{parent_id: top.id}
        |> PolicyMiddle.new()
        |> create()

      {:ok, _chained} =
        %{parent_id: middle.id}
        |> PolicyChained.new()
        |> create()

      html = render_page_html(Module173, %Server{user_id: user.id})

      assert carried_ids(html, PolicyMiddle) == [middle.id]
      assert carried_ids(html, PolicyEntity) == [top.id]
    end

    test "hands the template no relationship the rules read" do
      %{user: user} = create_parented_entities()

      html = render_page_html(Module173, %Server{user_id: user.id})

      not_included = inspect(%NotIncluded{relationship: :parent})

      assert String.contains?(html, "parents = #{not_included},#{not_included}")
    end

    test "carries no rule's rows when no client checks permissions" do
      dump_query_cache(QueryCacheStub, [Module172], false)
      QueryCache.init(nil)

      %{user: user} = create_parented_entities()

      html = render_page_html(Module173, %Server{user_id: user.id})

      assert carried_ids(html, PolicyParent) == []
    end
  end

  # A count has no rows behind it, so carried rows cannot re-derive one - the number itself
  # travels, keyed by the field and the arguments that answered it.
  describe "the counts a page hands its client" do
    setup do
      setup_page_rendering([
        {Module167, :dummy_module_167_digest},
        {Module175, :dummy_module_175_digest}
      ])

      dump_query_cache(QueryCacheStub, [Module166, Module174])
      QueryCache.init(nil)

      :ok
    end

    # Read back through a JSON decoder rather than matched as a substring: the counts are printed
    # into the boot data block, so their spelling carries escapes an HTML parser must not read as
    # markup - and what this test is about is the counts, not how they are spelled.
    test "carries the count each instance of a count field answered" do
      create_entities()

      counts =
        Module175
        |> render_page_html()
        |> boot_data()
        |> Map.fetch!("syncCounts")

      assert counts == %{
               "#{inspect(Module174)}/total/false" => 1,
               "#{inspect(Module174)}/total/true" => 2
             }
    end

    test "carries nothing for a page whose fields count nothing" do
      html = render_page_html(Module167)

      assert String.contains?(html, ~s|"syncCounts":{}|)
    end
  end

  # A permission check reads no rows - it asks whether a grant exists - so the rows behind its
  # answer are looked up once the render's questions are all in, and carried like any others.
  # Without them the client's first render would deny what the server just allowed.
  describe "the grants a page hands its client" do
    setup do
      setup_page_rendering([{Module126, :dummy_module_126_digest}])

      dump_query_cache(QueryCacheStub, [])
      QueryCache.init(nil)

      :ok
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

      Auth.grant_role(user, :viewer, entity)

      html = render_page_html(Module126, %Server{user_id: user.id}, %{entity_id: entity.id})

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

      html = render_page_html(Module126, %Server{user_id: user.id}, %{entity_id: entity.id})

      assert String.contains?(html, "may read = false")
      refute String.contains?(html, @role_grant_type)
    end

    test "carries no grant row for an anonymous session" do
      {:ok, entity} =
        %{priority: 5}
        |> PolicyEntity.new()
        |> create()

      html = render_page_html(Module126, %Server{}, %{entity_id: entity.id})

      assert String.contains?(html, "may read = false")
      refute String.contains?(html, @role_grant_type)
    end
  end

  describe "current-user context" do
    setup do
      setup_page_rendering([{Module131, :dummy_module_131_digest}])

      :ok
    end

    test "exposes the session user's row to a from_context prop" do
      user =
        %{email: "renderer_2@example.com"}
        |> Module14.new()
        |> DB.create!()

      html = render_page_html(Module131, %Server{user_id: user.id})

      assert String.contains?(html, "current user = renderer_2@example.com")
    end

    test "hands over the row with its server-only attributes already replaced by the sentinel" do
      user =
        %{email: "renderer_5@example.com", password_hash: "hash_9dTf"}
        |> Module14.new()
        |> DB.create!()

      %{component_registry: component_registry} =
        render_page(Module131, %{}, %Server{user_id: user.id}, @page_opts)

      context_user = component_registry["page"].struct.emitted_context[{Hologram, :user}]

      assert context_user.password_hash == %ServerOnly{attribute: :password_hash}
      assert context_user.email == "renderer_5@example.com"
    end

    test "exposes nil for an anonymous session" do
      html = render_page_html(Module131)

      assert String.contains?(html, "current user = none")
    end

    test "exposes nil when no row carries the session user id" do
      dangling_user_id = Entity.generate_id()

      html = render_page_html(Module131, %Server{user_id: dangling_user_id})

      assert String.contains?(html, "current user = none")
    end

    test "exposes nil for a session user id that is not a canonical entity id" do
      html = render_page_html(Module131, %Server{user_id: 7})

      assert String.contains?(html, "current user = none")
    end
  end
end
