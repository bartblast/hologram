defmodule Hologram.ControllerTest do
  use Hologram.Test.BasicCase, async: false

  import ExUnit.CaptureLog
  import Hologram.Controller
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Commons.SystemUtils
  alias Hologram.Compiler.Encoder
  alias Hologram.Realtime
  alias Hologram.Realtime.Handshake
  alias Hologram.Realtime.Receipt
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Realtime.Tombstone
  alias Hologram.Router.SearchTree
  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.CSRFProtection
  alias Hologram.Runtime.Session
  alias Hologram.Server
  alias Hologram.Template.Renderer
  alias Hologram.Test.Fixtures.Controller.Module1
  alias Hologram.Test.Fixtures.Controller.Module10
  alias Hologram.Test.Fixtures.Controller.Module11
  alias Hologram.Test.Fixtures.Controller.Module12
  alias Hologram.Test.Fixtures.Controller.Module13
  alias Hologram.Test.Fixtures.Controller.Module14
  alias Hologram.Test.Fixtures.Controller.Module15
  alias Hologram.Test.Fixtures.Controller.Module18
  alias Hologram.Test.Fixtures.Controller.Module19
  alias Hologram.Test.Fixtures.Controller.Module2
  alias Hologram.Test.Fixtures.Controller.Module20
  alias Hologram.Test.Fixtures.Controller.Module21
  alias Hologram.Test.Fixtures.Controller.Module22
  alias Hologram.Test.Fixtures.Controller.Module23
  alias Hologram.Test.Fixtures.Controller.Module24
  alias Hologram.Test.Fixtures.Controller.Module25
  alias Hologram.Test.Fixtures.Controller.Module26
  alias Hologram.Test.Fixtures.Controller.Module27
  alias Hologram.Test.Fixtures.Controller.Module28
  alias Hologram.Test.Fixtures.Controller.Module29
  alias Hologram.Test.Fixtures.Controller.Module3
  alias Hologram.Test.Fixtures.Controller.Module30
  alias Hologram.Test.Fixtures.Controller.Module31
  alias Hologram.Test.Fixtures.Controller.Module32
  alias Hologram.Test.Fixtures.Controller.Module34
  alias Hologram.Test.Fixtures.Controller.Module35
  alias Hologram.Test.Fixtures.Controller.Module4
  alias Hologram.Test.Fixtures.Controller.Module5
  alias Hologram.Test.Fixtures.Controller.Module6
  alias Hologram.Test.Fixtures.Controller.Module8
  alias Hologram.Test.Fixtures.Controller.Module9

  @unmasked_csrf_token CSRFProtection.generate_unmasked_token()
  @masked_csrf_token CSRFProtection.get_masked_token(@unmasked_csrf_token)

  @csrf_token_session_key CSRFProtection.session_key()
  @hologram_session_id "test-session-id"
  @replica_id "test-replica-id"
  @replica_token "test-replica-token"

  @session %{
    @csrf_token_session_key => @unmasked_csrf_token,
    hologram_session_id: @hologram_session_id
  }

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry
  use_module_stub :page_module_resolver

  setup :set_mox_global

  setup do
    # Both the page-render and command paths address the connection over PubSub, so it
    # must be up first - the same order Hologram.Application starts them in.
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(SubscriptionRegistry)
    start_supervised!(SubscriptionRegistry)

    :ok
  end

  defp binary_to_hex(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.map(&String.downcase/1)
    |> Enum.map_join(&String.pad_leading(&1, 2, "0"))
  end

  # Create a test connection with parsed JSON body_params (simulating what Plug.Parsers does)
  defp conn_with_parsed_json(method, path, parsed_json, session \\ @session) do
    method
    |> Plug.Test.conn(path, "")
    |> Plug.Test.init_test_session(session)
    |> Map.put(:body_params, %{"_json" => parsed_json})
  end

  defp execute_command_request(payload) do
    parsed_json =
      payload
      |> serialize_payload()
      |> Jason.decode!()

    :post
    |> conn_with_parsed_json("/hologram/command", parsed_json)
    |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
    |> handle_command_request()
  end

  defp execute_successful_command_request do
    execute_command_request(%{
      module: Module6,
      name: :my_command_a,
      params: %{},
      target: "my_target_1"
    })
  end

  defp extract_instance_id(resp_body) do
    [_full, instance_id] =
      Regex.run(~r/globalThis\.Hologram\.instanceId = "([^"]+)";/, resp_body)

    instance_id
  end

  defp handshake_request_body(instance_id, receipts) do
    serialized_receipts =
      Enum.map(receipts, fn token -> "b0#{binary_to_hex(token)}" end)

    [
      2,
      %{
        "t" => "m",
        "d" => [
          ["ainstance_id", "b0#{binary_to_hex(instance_id)}"],
          ["areceipts", %{"t" => "l", "d" => serialized_receipts}]
        ]
      }
    ]
  end

  defp page_request_body(instance_id \\ "test-instance-id", client_claimed_sub_keys \\ []) do
    serialized_keys =
      Enum.map(client_claimed_sub_keys, fn {channel, cid} ->
        %{"t" => "t", "d" => ["a#{channel}", "b0#{binary_to_hex(cid)}"]}
      end)

    [
      2,
      %{
        "t" => "m",
        "d" => [
          ["aclient_claimed_sub_keys", %{"t" => "l", "d" => serialized_keys}],
          ["ainstance_id", "b0#{binary_to_hex(instance_id)}"]
        ]
      }
    ]
  end

  defp post_handshake(instance_id, session_data, receipts \\ []) do
    parsed_json =
      instance_id
      |> handshake_request_body(receipts)
      |> Jason.encode!()
      |> Jason.decode!()

    :post
    |> Plug.Test.conn("/hologram/sse/handshake", "")
    |> Plug.Test.init_test_session(session_data)
    |> Map.put(:body_params, %{"_json" => parsed_json})
    |> handle_sse_handshake_request()
  end

  defp render_page_with_instance(page_module, instance_id, client_claimed_sub_keys \\ []) do
    :get
    |> Plug.Test.conn("/")
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.fetch_cookies()
    |> handle_page_request(page_module, %{}, client_claimed_sub_keys,
      initial_page?: true,
      instance_id: instance_id,
      csrf_token: @masked_csrf_token,
      replica_id: @replica_id,
      replica_token: @replica_token
    )
  end

  defp serialize_params(params) when params == %{} do
    %{"t" => "m", "d" => []}
  end

  defp serialize_params(params) do
    serialized_params =
      Enum.map(params, fn {key, value} ->
        ["a#{key}", "i#{value}"]
      end)

    %{"t" => "m", "d" => serialized_params}
  end

  # Serialize payload in the format expected by Deserializer.deserialize/1
  # Version 2 format: [version, serialized_data]
  defp serialize_payload(payload) do
    instance_id = Map.get(payload, :instance_id, "test-instance-id")

    serialized_sub_receipts =
      payload
      |> Map.get(:sub_receipts, [])
      |> Enum.map(fn token -> "b0#{binary_to_hex(token)}" end)

    serialized_map_data = [
      ["ainstance_id", "b0#{binary_to_hex(instance_id)}"],
      ["amodule", "a#{payload.module}"],
      ["aname", "a#{payload.name}"],
      ["aparams", serialize_params(payload.params)],
      ["asub_receipts", %{"t" => "l", "d" => serialized_sub_receipts}],
      ["atarget", "b0#{binary_to_hex(payload.target)}"]
    ]

    Jason.encode!([2, %{"t" => "m", "d" => serialized_map_data}])
  end

  defp subsequent_page_request_conn(path, session_data \\ %{}) do
    :post
    |> Plug.Test.conn(path, "")
    |> Plug.Test.init_test_session(session_data)
    |> Map.put(:body_params, %{"_json" => page_request_body()})
  end

  # Gives the resolver a search tree holding just the given pages, rather than standing up the
  # registry process over whatever pages happen to be compiled.
  defp stub_page_module_resolver(page_modules) do
    persistent_term_key = :controller_test_search_tree

    stub(PageModuleResolverMock, :persistent_term_key, fn -> persistent_term_key end)

    search_tree =
      Enum.reduce(page_modules, %SearchTree.Node{}, fn page_module, acc ->
        SearchTree.add_route(acc, page_module.__route__(), page_module)
      end)

    :persistent_term.put(persistent_term_key, search_tree)

    on_exit(fn -> :persistent_term.erase(persistent_term_key) end)

    :ok
  end

  setup do
    setup_asset_path_registry(AssetPathRegistryStub)
    AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

    setup_asset_manifest_cache(AssetManifestCacheStub)

    setup_page_digest_registry(PageDigestRegistryStub)
  end

  describe "extract_params/2" do
    test "extracts params from URL path" do
      url_path = "/hologram-test-fixtures-runtime-controller-module1/111/ccc/222"

      assert extract_params(url_path, Module1) == %{"aaa" => "111", "bbb" => "222"}
    end

    test "decodes URL-encoded params" do
      url_path = "/hologram-test-fixtures-runtime-controller-module1/hello%20world/ccc/foo%2Fbar"

      assert extract_params(url_path, Module1) == %{"aaa" => "hello world", "bbb" => "foo/bar"}
    end
  end

  describe "apply_cookie_ops/2" do
    setup do
      [conn: Plug.Test.conn(:get, "/")]
    end

    test "applies put operation with default cookie opts", %{conn: conn} do
      cookie_struct = %Cookie{value: "test_value"}
      cookie_ops = %{"test_cookie" => cookie_struct}

      result = apply_cookie_ops(conn, cookie_ops)

      assert result.resp_cookies == %{
               "test_cookie" => %{
                 value: "%Hg20AAAAKdGVzdF92YWx1ZQ",
                 http_only: true,
                 same_site: "Lax",
                 secure: true
               }
             }
    end

    test "applies put operation with custom cookie opts", %{conn: conn} do
      cookie_struct = %Cookie{
        value: "test_value",
        domain: "example.com",
        http_only: false,
        max_age: 3_600,
        path: "/admin",
        same_site: :strict,
        secure: false
      }

      cookie_ops = %{"test_cookie" => cookie_struct}

      result = apply_cookie_ops(conn, cookie_ops)

      assert result.resp_cookies == %{
               "test_cookie" => %{
                 value: "%Hg20AAAAKdGVzdF92YWx1ZQ",
                 domain: "example.com",
                 http_only: false,
                 path: "/admin",
                 same_site: "Strict",
                 secure: false,
                 max_age: 3_600
               }
             }
    end

    test "applies delete operation", %{conn: conn} do
      cookie_ops = %{"existing_cookie" => :delete}

      result = apply_cookie_ops(conn, cookie_ops)

      assert result.resp_cookies == %{
               "existing_cookie" => %{universal_time: {{1970, 1, 1}, {0, 0, 0}}, max_age: 0}
             }
    end

    test "applies multiple operations", %{conn: conn} do
      cookie_struct_1 = %Cookie{value: "new_value_1", path: "/path-1"}
      cookie_struct_2 = %Cookie{value: "new_value_2", path: "/path-2"}

      cookie_ops = %{
        "new_cookie_1" => cookie_struct_1,
        "new_cookie_2" => cookie_struct_2,
        "old_cookie" => :delete
      }

      result = apply_cookie_ops(conn, cookie_ops)

      # Check new cookies are set
      assert result.resp_cookies["new_cookie_1"][:value]
      assert result.resp_cookies["new_cookie_2"][:value]

      # Check old cookie is deleted
      assert result.resp_cookies["old_cookie"] == %{
               universal_time: {{1970, 1, 1}, {0, 0, 0}},
               max_age: 0
             }
    end

    test "handles empty cookie operations", %{conn: conn} do
      cookie_ops = %{}

      result = apply_cookie_ops(conn, cookie_ops)

      assert result.resp_cookies == %{}
    end

    test "filters out nil cookie opts", %{conn: conn} do
      cookie_struct = %Cookie{
        value: "test_value",
        domain: nil,
        http_only: true,
        max_age: nil,
        path: "/test-path",
        same_site: :strict,
        secure: nil
      }

      cookie_ops = %{"test_cookie" => cookie_struct}

      result = apply_cookie_ops(conn, cookie_ops)

      cookie_data = result.resp_cookies["test_cookie"]

      # Should include non-nil opts
      assert cookie_data.http_only == true
      assert cookie_data.path == "/test-path"
      assert cookie_data.same_site == "Strict"

      # Should not include nil opts
      refute Map.has_key?(cookie_data, :domain)
      refute Map.has_key?(cookie_data, :max_age)
      refute Map.has_key?(cookie_data, :secure)
    end
  end

  describe "apply_session_ops/2" do
    setup do
      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{"existing_key" => "existing_value"})

      [conn: conn]
    end

    test "applies put operation", %{conn: conn} do
      session_ops = %{"new_key" => {:put, "new_value"}}

      result = apply_session_ops(conn, session_ops)

      assert result.private == %{
               plug_session_fetch: :done,
               plug_session: %{"existing_key" => "existing_value", "new_key" => "new_value"},
               plug_session_info: :write
             }
    end

    test "applies delete operation", %{conn: conn} do
      session_ops = %{"existing_key" => :delete}

      result = apply_session_ops(conn, session_ops)

      assert result.private == %{
               plug_session_fetch: :done,
               plug_session: %{},
               plug_session_info: :write
             }
    end

    test "applies multiple operations", %{conn: conn} do
      session_ops = %{
        "new_key_1" => {:put, "new_value_1"},
        "new_key_2" => {:put, "new_value_2"},
        "existing_key" => :delete
      }

      result = apply_session_ops(conn, session_ops)

      assert result.private == %{
               plug_session_fetch: :done,
               plug_session: %{"new_key_1" => "new_value_1", "new_key_2" => "new_value_2"},
               plug_session_info: :write
             }
    end

    test "handles empty cookie operations", %{conn: conn} do
      session_ops = %{}

      result = apply_session_ops(conn, session_ops)

      assert result.private == %{
               plug_session_fetch: :done,
               plug_session: %{"existing_key" => "existing_value"},
               plug_session_info: :write
             }
    end
  end

  describe "build_page_data_payload/1" do
    setup do
      fields = %{
        mount_data: %{
          actor_user_id: "123",
          asset_manifest: "{\"/hologram/runtime.js\": \"/hologram/runtime-1234.js\"};",
          component_registry: ~s/Type.map([[Type.bitstring("page"), Type.map([])]])/,
          page_module: Encoder.encode_term!(Module1),
          page_params: ~s/Type.map([])/,
          sync_counts: ~s/{"posts": 2}/,
          sync_rows: ~s/{"posts": []}/
        },
        page_digest: "abcdef1234567890",
        self_echoes: [],
        sub_receipt_adds: [],
        sub_receipt_drops: [],
        tree: [{:element, "div", [{"$key", [text: "a1b2c3:0"]}], [{:text, "abc"}]}]
      }

      [fields: fields]
    end

    test "carries the digest naming the page's bundle", %{fields: fields} do
      assert %{pageDigest: "abcdef1234567890", type: "page"} = build_page_data_payload(fields)
    end

    # Each value lands under its own key, and they are encoded differently: everything but the tree
    # as JavaScript the client evaluates, the tree as data it gets already parsed.
    test "encodes each value under its own key", %{fields: fields} do
      payload = build_page_data_payload(fields)

      assert payload.componentRegistry == fields.mount_data.component_registry
      assert payload.pageModule == fields.mount_data.page_module
      assert payload.pageParams == fields.mount_data.page_params
      assert payload.selfEchoes == Encoder.encode_term!(fields.self_echoes)
      assert payload.subReceiptAdds == Encoder.encode_term!(fields.sub_receipt_adds)
      assert payload.subReceiptDrops == Encoder.encode_term!(fields.sub_receipt_drops)
      assert payload.tree == Renderer.encode_tree(fields.tree)
    end

    # Everything a mount reads travels beside the tree rather than inside it, so it is readable
    # before the render is patched in and never pays the escaping round trip the tree would cost.
    test "carries what a mount reads beside the tree", %{fields: fields} do
      assert fields
             |> build_page_data_payload()
             |> Map.keys()
             |> Enum.sort() == [
               :actorUserId,
               :componentRegistry,
               :pageDigest,
               :pageModule,
               :pageParams,
               :selfEchoes,
               :subReceiptAdds,
               :subReceiptDrops,
               :syncCounts,
               :syncRows,
               :tree,
               :type
             ]
    end

    # The asset manifest is a global the initial document sets once, not something a mount reads,
    # so it has no business on this path even though the renderer hands it back alongside.
    test "leaves the asset manifest out", %{fields: fields} do
      payload = build_page_data_payload(fields)

      encoded = Jason.encode!(payload)

      refute Map.has_key?(payload, :assetManifest)
      refute String.contains?(encoded, "runtime-1234")
    end

    test "survives the JSON encoding it is sent over", %{fields: fields} do
      payload = build_page_data_payload(fields)

      decoded =
        payload
        |> Jason.encode!()
        |> Jason.decode!()

      assert decoded["type"] == "page"
      assert decoded["pageDigest"] == "abcdef1234567890"
      assert decoded["tree"] == payload.tree
      assert decoded["componentRegistry"] == payload.componentRegistry
    end

    test "describes a redirect to a page the client can ask for itself" do
      payload = build_page_data_payload({:redirect, "/my-target", Module1, %{key: "value"}})

      assert payload.type == "redirect"
      assert payload.to == "/my-target"
      assert payload.pageModule == Encoder.encode_term!(Module1)
      assert payload.pageParams == Encoder.encode_term!(%{key: "value"})
    end

    # The page clause matches a map and the redirect clauses match tuples, so nothing a page
    # payload gained can leak into a redirect one.
    test "a redirect carries none of the page fields" do
      payload = build_page_data_payload({:redirect, "/my-target", Module1, %{key: "value"}})

      keys =
        payload
        |> Map.keys()
        |> Enum.sort()

      assert keys == [:pageModule, :pageParams, :to, :type]
    end

    # A target no page owns is the client's cue to hand it to the browser, so it carries nothing to
    # ask for.
    test "describes a redirect to a target no page owns" do
      assert build_page_data_payload({:redirect, "https://example.com/x", nil, nil}) == %{
               to: "https://example.com/x",
               type: "redirect"
             }
    end

    test "redirect survives the JSON encoding it is sent over" do
      payload = build_page_data_payload({:redirect, "/my-target", Module1, %{key: "value"}})

      decoded =
        payload
        |> Jason.encode!()
        |> Jason.decode!()

      assert decoded["type"] == "redirect"
      assert decoded["to"] == "/my-target"
      assert decoded["pageModule"] == payload.pageModule
    end
  end

  describe "resolve_redirect_target/1" do
    setup do
      stub_page_module_resolver([Module1, Module11, Module32, Module4])
    end

    test "resolves a path to the page that owns it" do
      to = Module4.__route__()

      assert resolve_redirect_target(to) == {:redirect, to, Module4, %{}}
    end

    test "casts params carried by the path" do
      assert {:redirect, _to, Module1, %{aaa: 111, bbb: 222}} =
               resolve_redirect_target(
                 "/hologram-test-fixtures-runtime-controller-module1/111/ccc/222"
               )
    end

    test "decodes params carried by the path" do
      assert {:redirect, _to, Module11, %{param_a: "hello world", param_b: "x"}} =
               resolve_redirect_target(
                 "/hologram-test-fixtures-controller-module11/hello%20world/x"
               )
    end

    # Module32 declares params its route does not name, so these can only have come from the query
    # string, and param_b being an integer shows they are cast rather than passed through.
    test "casts params carried by the query string" do
      assert {:redirect, _to, Module32, %{param_a: "hello world", param_b: 42}} =
               resolve_redirect_target(
                 "/hologram-test-fixtures-controller-module32?param_a=hello+world&param_b=42"
               )
    end

    # A redirect target is a URL someone wrote, and it can carry params meant for something other
    # than the page. Casting those raises, which would turn the redirect into a 500.
    test "leaves out a query param the page does not declare" do
      to = Module4.__route__() <> "?utm_source=x"

      assert resolve_redirect_target(to) == {:redirect, to, Module4, %{}}
    end

    test "keeps the params the page declares when undeclared ones travel with them" do
      to =
        "/hologram-test-fixtures-controller-module11/hello%20world/x?utm_source=y"

      assert {:redirect, ^to, Module11, %{param_a: "hello world", param_b: "x"}} =
               resolve_redirect_target(to)
    end

    test "resolves a target no page owns to no module" do
      assert resolve_redirect_target("https://example.com/x") ==
               {:redirect, "https://example.com/x", nil, nil}
    end

    # The same path can exist here and elsewhere, so a target naming another origin has to stay
    # the browser's business even when this app happens to own a route spelled the same way.
    test "resolves a target on another origin to no module, path collision or not" do
      to = "https://example.com" <> Module4.__route__()

      assert resolve_redirect_target(to) == {:redirect, to, nil, nil}
    end

    test "resolves a protocol-relative target to no module" do
      to = "//example.com" <> Module4.__route__()

      assert resolve_redirect_target(to) == {:redirect, to, nil, nil}
    end

    # A scheme with no authority still names something other than a path within this app.
    test "resolves a target carrying a scheme to no module" do
      to = "https://" <> Module4.__route__()

      assert resolve_redirect_target(to) == {:redirect, to, nil, nil}
    end

    test "resolves a path the framework itself serves to no module" do
      assert resolve_redirect_target("/hologram/ping") ==
               {:redirect, "/hologram/ping", nil, nil}
    end
  end

  describe "handle_command_request/1" do
    setup do
      wait_for_process_cleanup(Tombstone)
      start_supervised!(Tombstone)

      :ok
    end

    test "returns 403 when CSRF token is missing from header" do
      payload = %{
        module: Module6,
        name: :my_command_a,
        params: %{},
        target: "my_target_1"
      }

      parsed_json =
        payload
        |> serialize_payload()
        |> Jason.decode!()

      conn =
        :post
        |> conn_with_parsed_json("/hologram/command", parsed_json)
        # No X-Csrf-Token header provided
        |> handle_command_request()

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 403
      assert conn.resp_body == "Forbidden"
    end

    test "returns 403 when CSRF token header is empty" do
      payload = %{
        module: Module6,
        name: :my_command_a,
        params: %{},
        target: "my_target_1"
      }

      parsed_json =
        payload
        |> serialize_payload()
        |> Jason.decode!()

      conn =
        :post
        |> conn_with_parsed_json("/hologram/command", parsed_json)
        |> Plug.Conn.put_req_header("x-csrf-token", "")
        |> handle_command_request()

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 403
      assert conn.resp_body == "Forbidden"
    end

    test "returns 403 when session CSRF token is missing" do
      payload = %{
        module: Module6,
        name: :my_command_a,
        params: %{},
        target: "my_target_1"
      }

      parsed_json =
        payload
        |> serialize_payload()
        |> Jason.decode!()

      conn =
        :post
        |> conn_with_parsed_json("/hologram/command", parsed_json, %{})
        # No session token, but provide header token
        |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
        |> handle_command_request()

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 403
      assert conn.resp_body == "Forbidden"
    end

    test "returns 403 when CSRF token validation fails" do
      payload = %{
        module: Module6,
        name: :my_command_a,
        params: %{},
        target: "my_target_1"
      }

      {another_masked_token, _another_unmasked_token} = CSRFProtection.generate_tokens()

      parsed_json =
        payload
        |> serialize_payload()
        |> Jason.decode!()

      conn =
        :post
        |> conn_with_parsed_json("/hologram/command", parsed_json)
        # Use a different masked token that won't validate against the session token
        |> Plug.Conn.put_req_header("x-csrf-token", another_masked_token)
        |> handle_command_request()

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 403
      assert conn.resp_body == "Forbidden"
    end

    test "logs warning when CSRF token validation fails" do
      payload = %{
        module: Module6,
        name: :my_command_a,
        params: %{},
        target: "my_target_1"
      }

      parsed_json =
        payload
        |> serialize_payload()
        |> Jason.decode!()

      log =
        capture_log(fn ->
          :post
          |> conn_with_parsed_json("/hologram/command", parsed_json)
          # No X-Csrf-Token header provided
          |> handle_command_request()
        end)

      assert log =~ "CSRF token validation failed"
    end

    test "processes command successfully when CSRF token validation succeeds" do
      conn = execute_successful_command_request()
      response = Jason.decode!(conn.resp_body)

      assert response == %{
               "action" => ~s'Type.atom("nil")',
               "selfEchoes" => "Type.list([])",
               "status" => 1,
               "subReceiptAdds" => "Type.list([])",
               "subReceiptDrops" => "Type.list([])"
             }
    end

    test "skips the command and sends the terminal response when middleware terminates" do
      conn =
        execute_command_request(%{
          module: Module23,
          name: :my_command,
          params: %{},
          target: "my_target_1"
        })

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 403
    end

    test "runs middleware before the command and passes the enriched server" do
      conn =
        execute_command_request(%{
          module: Module24,
          name: :my_command,
          params: %{},
          target: "my_target_1"
        })

      response = Jason.decode!(conn.resp_body)

      assert response["action"] =~ "injected_by_middleware"
    end

    test "runs middleware as the session user" do
      session = Map.put(@session, :hologram_user_id, "019ff5c2-0000-7000-8000-000000000001")

      parsed_json =
        %{
          module: Module34,
          name: :my_command_reporting_middleware_actor,
          params: %{},
          target: "my_target_1"
        }
        |> serialize_payload()
        |> Jason.decode!()

      conn =
        :post
        |> conn_with_parsed_json("/hologram/command", parsed_json, session)
        |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
        |> handle_command_request()

      response = Jason.decode!(conn.resp_body)

      assert response["action"] =~ "019ff5c2-0000-7000-8000-000000000001"
    end

    test "establishes a Hologram session ID when absent" do
      payload = %{
        module: Module6,
        name: :my_command_a,
        params: %{},
        target: "my_target_1"
      }

      parsed_json =
        payload
        |> serialize_payload()
        |> Jason.decode!()

      session_without_hologram_id = %{@csrf_token_session_key => @unmasked_csrf_token}

      conn =
        :post
        |> conn_with_parsed_json("/hologram/command", parsed_json, session_without_hologram_id)
        |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
        |> handle_command_request()

      session_id = Session.get_session_id(conn)

      assert {:ok, _info} = UUID.info(session_id)
    end

    test "exposes the target as server.cid for the command handler" do
      payload = %{
        module: Module6,
        name: :my_command_accessing_cid,
        params: %{},
        target: "my_target_1"
      }

      conn = execute_command_request(payload)
      response = Jason.decode!(conn.resp_body)

      assert response["action"] ==
               ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("my_action_echoing_cid")], [Type.atom("params"), Type.map([[Type.atom("cid"), Type.bitstring("my_target_1")]])], [Type.atom("target"), Type.bitstring("my_target_1")]])'
    end

    test "encodes next action params with server-only attribute values replaced by the sentinel" do
      payload = %{
        module: Module6,
        name: :my_command_returning_entity_row,
        params: %{},
        target: "my_target_1"
      }

      conn = execute_command_request(payload)
      response = Jason.decode!(conn.resp_body)

      expected_sentinel =
        ~s'[Type.atom("token"), Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Entity.ServerOnly")], [Type.atom("attribute"), Type.atom("token")]])]'

      assert String.contains?(response["action"], expected_sentinel)
      refute String.contains?(response["action"], "note_secret_v5")
      refute String.contains?(response["action"], "tok_H2sB")
    end

    test "extracts instance_id from payload and exposes it via server.instance_id" do
      payload = %{
        instance_id: "my-instance-id",
        module: Module6,
        name: :my_command_accessing_instance_id,
        params: %{},
        target: "my_target_1"
      }

      conn = execute_command_request(payload)
      response = Jason.decode!(conn.resp_body)

      assert response["action"] ==
               ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("my_action_echoing_instance_id")], [Type.atom("params"), Type.map([[Type.atom("instance_id"), Type.bitstring("my-instance-id")]])], [Type.atom("target"), Type.bitstring("my_target_1")]])'
    end

    test "pre-populates server.subscriptions with only the target component's receipts" do
      # No registry entry is registered anywhere - the subscriptions come entirely from
      # the tab's own signed receipts, which is what makes this work when the command
      # lands on a node that does not hold the connection.
      payload = %{
        instance_id: "my-instance-id",
        module: Module6,
        name: :my_command_accessing_subscriptions,
        params: %{},
        sub_receipts: [
          Receipt.issue(:room_a, "my_target_1", "my-instance-id", nil),
          Receipt.issue(:room_b, "other_target", "my-instance-id", nil)
        ],
        target: "my_target_1"
      }

      conn = execute_command_request(payload)
      response = Jason.decode!(conn.resp_body)

      assert response["action"] ==
               ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("my_action_echoing_subscriptions")], [Type.atom("params"), Type.map([[Type.atom("subscriptions"), Type.list([Type.tuple([Type.atom("room_a"), Type.bitstring("my_target_1")])])]])], [Type.atom("target"), Type.bitstring("my_target_1")]])'
    end

    test "ignores a receipt whose binding has been tombstoned" do
      token = Receipt.issue(:room_a, "my_target_1", "my-instance-id", nil)
      {:ok, %Receipt{created_at: receipt_created_at}} = Receipt.verify(token)

      # Anchored to the receipt rather than to the clock, since a tombstone stamped in an
      # earlier millisecond than the receipt legitimately does not reject it.
      Tombstone.insert(
        {{:instance, "my-instance-id"}, :room_a, "my_target_1"},
        receipt_created_at + 1
      )

      payload = %{
        instance_id: "my-instance-id",
        module: Module6,
        name: :my_command_accessing_subscriptions,
        params: %{},
        sub_receipts: [token],
        target: "my_target_1"
      }

      conn = execute_command_request(payload)
      response = Jason.decode!(conn.resp_body)

      assert response["action"] =~ ~s'Type.atom("subscriptions"), Type.list([])'
    end

    test "pre-populates server.subscriptions to an empty list when no registry entry exists" do
      payload = %{
        instance_id: "test-unknown-instance-id",
        module: Module6,
        name: :my_command_accessing_subscriptions,
        params: %{},
        target: "my_target_1"
      }

      conn = execute_command_request(payload)
      response = Jason.decode!(conn.resp_body)

      assert response["action"] ==
               ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("my_action_echoing_subscriptions")], [Type.atom("params"), Type.map([[Type.atom("subscriptions"), Type.list([])]])], [Type.atom("target"), Type.bitstring("my_target_1")]])'
    end

    test "drives SubscriptionRegistry.apply_deltas after a command calls put_subscription" do
      :ok = SubscriptionRegistry.register_connection("my-instance-id", self())
      :ok = SubscriptionRegistry.update_identity("my-instance-id", @hologram_session_id, nil)

      execute_command_request(%{
        instance_id: "my-instance-id",
        module: Module6,
        name: :my_command_putting_subscription,
        params: %{},
        target: "my_target_1"
      })

      assert SubscriptionRegistry.bindings_of("my-instance-id") == %{
               {:room_a, "my_target_1"} => nil
             }
    end

    test "drives SubscriptionRegistry.apply_deltas after a command calls delete_subscription" do
      :ok = SubscriptionRegistry.register_connection("my-instance-id", self())
      :ok = SubscriptionRegistry.update_identity("my-instance-id", @hologram_session_id, nil)

      SubscriptionRegistry.apply_deltas(
        "my-instance-id",
        [{:room_a, "my_target_1"}],
        [],
        "seed-user-id"
      )

      execute_command_request(%{
        instance_id: "my-instance-id",
        module: Module6,
        name: :my_command_deleting_subscription,
        params: %{},
        target: "my_target_1"
      })

      assert SubscriptionRegistry.bindings_of("my-instance-id") == %{}
    end

    test "applies adds and drops together when a command calls put_subscription and delete_subscription" do
      :ok = SubscriptionRegistry.register_connection("my-instance-id", self())
      :ok = SubscriptionRegistry.update_identity("my-instance-id", @hologram_session_id, nil)

      SubscriptionRegistry.apply_deltas(
        "my-instance-id",
        [{:room_a, "my_target_1"}],
        [],
        "seed-user-id"
      )

      execute_command_request(%{
        instance_id: "my-instance-id",
        module: Module6,
        name: :my_command_putting_and_deleting_subscriptions,
        params: %{},
        target: "my_target_1"
      })

      assert SubscriptionRegistry.bindings_of("my-instance-id") == %{
               {:room_b, "my_target_1"} => nil
             }
    end

    test "writes an instance-level binding-shape tombstone for each dropped key" do
      :ok = SubscriptionRegistry.register_connection("my-instance-id", self())
      :ok = SubscriptionRegistry.update_identity("my-instance-id", @hologram_session_id, nil)

      SubscriptionRegistry.apply_deltas(
        "my-instance-id",
        [{:room_a, "my_target_1"}],
        [],
        "seed-user-id"
      )

      execute_command_request(%{
        instance_id: "my-instance-id",
        module: Module6,
        name: :my_command_deleting_subscription,
        params: %{},
        target: "my_target_1"
      })

      tombstone_key = {{:instance, "my-instance-id"}, :room_a, "my_target_1"}

      assert [{^tombstone_key, _created_at}] =
               :ets.lookup(Tombstone.ets_table_name(), tombstone_key)
    end

    test "writes no tombstones when the command handler raises before subscription_ops flushes" do
      :ok = SubscriptionRegistry.register_connection("my-instance-id", self())
      :ok = SubscriptionRegistry.update_identity("my-instance-id", @hologram_session_id, nil)

      SubscriptionRegistry.apply_deltas(
        "my-instance-id",
        [{:room_a, "my_target_1"}],
        [],
        "seed-user-id"
      )

      payload = %{
        instance_id: "my-instance-id",
        module: Module6,
        name: :my_command_deleting_subscription_then_raising,
        params: %{},
        target: "my_target_1"
      }

      assert_raise RuntimeError, "boom", fn -> execute_command_request(payload) end

      assert :ets.tab2list(Tombstone.ets_table_name()) == []
    end

    test "leaves SubscriptionRegistry bindings unchanged when subscription_ops is empty" do
      :ok = SubscriptionRegistry.register_connection("my-instance-id", self())
      :ok = SubscriptionRegistry.update_identity("my-instance-id", @hologram_session_id, nil)

      SubscriptionRegistry.apply_deltas(
        "my-instance-id",
        [{:pre_existing, "page"}],
        [],
        "seed-user-id"
      )

      execute_command_request(%{
        instance_id: "my-instance-id",
        module: Module6,
        name: :my_command_a,
        params: %{},
        target: "my_target_1"
      })

      assert SubscriptionRegistry.bindings_of("my-instance-id") == %{
               {:pre_existing, "page"} => "seed-user-id"
             }
    end

    test "does not flush subscription_ops when the command raises" do
      :ok = SubscriptionRegistry.register_connection("my-instance-id", self())
      :ok = SubscriptionRegistry.update_identity("my-instance-id", @hologram_session_id, nil)

      payload = %{
        instance_id: "my-instance-id",
        module: Module6,
        name: :my_command_putting_subscription_then_raising,
        params: %{},
        target: "my_target_1"
      }

      assert_raise RuntimeError, "boom", fn -> execute_command_request(payload) end

      assert SubscriptionRegistry.bindings_of("my-instance-id") == %{}
    end

    test "embeds a receipt entry in the response for each newly-added subscription" do
      :ok = SubscriptionRegistry.register_connection("my-instance-id", self())
      :ok = SubscriptionRegistry.update_identity("my-instance-id", @hologram_session_id, nil)

      conn =
        execute_command_request(%{
          instance_id: "my-instance-id",
          module: Module6,
          name: :my_command_putting_subscription,
          params: %{},
          target: "my_target_1"
        })

      %{"subReceiptAdds" => encoded_sub_receipt_adds} = Jason.decode!(conn.resp_body)

      assert String.contains?(encoded_sub_receipt_adds, ~s'Type.atom("room_a")')
      assert String.contains?(encoded_sub_receipt_adds, ~s'Type.bitstring("my_target_1")')
    end

    test "embeds a drop entry in the response for each newly-dropped subscription" do
      :ok = SubscriptionRegistry.register_connection("my-instance-id", self())
      :ok = SubscriptionRegistry.update_identity("my-instance-id", @hologram_session_id, nil)

      SubscriptionRegistry.apply_deltas(
        "my-instance-id",
        [{:room_a, "my_target_1"}],
        [],
        "seed-user-id"
      )

      conn =
        execute_command_request(%{
          instance_id: "my-instance-id",
          module: Module6,
          name: :my_command_deleting_subscription,
          params: %{},
          target: "my_target_1"
        })

      %{"subReceiptDrops" => encoded_sub_receipt_drops} = Jason.decode!(conn.resp_body)

      assert String.contains?(encoded_sub_receipt_drops, ~s'Type.atom("room_a")')
      assert String.contains?(encoded_sub_receipt_drops, ~s'Type.bitstring("my_target_1")')
    end

    test "embeds adds and drops together when a command both puts and deletes subscriptions" do
      :ok = SubscriptionRegistry.register_connection("my-instance-id", self())
      :ok = SubscriptionRegistry.update_identity("my-instance-id", @hologram_session_id, nil)

      SubscriptionRegistry.apply_deltas(
        "my-instance-id",
        [{:room_a, "my_target_1"}],
        [],
        "seed-user-id"
      )

      conn =
        execute_command_request(%{
          instance_id: "my-instance-id",
          module: Module6,
          name: :my_command_putting_and_deleting_subscriptions,
          params: %{},
          target: "my_target_1"
        })

      %{
        "subReceiptAdds" => encoded_sub_receipt_adds,
        "subReceiptDrops" => encoded_sub_receipt_drops
      } =
        Jason.decode!(conn.resp_body)

      assert String.contains?(encoded_sub_receipt_adds, ~s'Type.atom("room_b")')
      assert String.contains?(encoded_sub_receipt_drops, ~s'Type.atom("room_a")')
    end

    test "updates Plug.Conn fields related to HTTP response and halts the pipeline when CSRF token validation succeeds" do
      payload = %{
        module: Module6,
        name: :my_command_a,
        params: %{},
        target: "my_target_1"
      }

      conn = execute_command_request(payload)

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 200
    end

    # TODO: uncomment when standalone Hologram is supported
    # test "initializes Hologram session" do
    #   payload = %{
    #     module: Module6,
    #     name: :my_command_a,
    #     params: %{},
    #     target: "my_target_1"
    #   }

    #   parsed_json =
    #     payload
    #     |> serialize_payload()
    #     |> Jason.decode!()

    #   conn =
    #     :post
    #     |> conn_with_parsed_json("/hologram/command", parsed_json)
    #     |> handle_command_request()

    #   assert Map.has_key?(conn.resp_cookies, "hologram_session")
    # end

    test "command with next action nil" do
      conn = execute_successful_command_request()
      response = Jason.decode!(conn.resp_body)

      assert response["action"] == ~s'Type.atom("nil")'
    end

    test "command with next action target not specified" do
      payload = %{
        module: Module6,
        name: :my_command_b,
        params: %{a: 1, b: 2},
        target: "my_target_1"
      }

      conn = execute_command_request(payload)
      response = Jason.decode!(conn.resp_body)

      assert response["action"] ==
               ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("my_action_b")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring("my_target_1")]])'
    end

    test "command with next action target specified" do
      payload = %{
        module: Module6,
        name: :my_command_c,
        params: %{a: 1, b: 2},
        target: "my_target_1"
      }

      conn = execute_command_request(payload)
      response = Jason.decode!(conn.resp_body)

      assert response["action"] ==
               ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("my_action_c")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring("my_target_2")]])'
    end

    test "command with encoding error for anonymous function" do
      payload = %{
        module: Module8,
        name: :my_command_8,
        params: %{},
        target: "my_target_1"
      }

      conn = execute_command_request(payload)
      response = Jason.decode!(conn.resp_body)

      expected_msg =
        if SystemUtils.otp_version() >= 23 do
          "term contains a function that is not a named function capture"
        else
          "term contains a function that is not a remote function capture"
        end

      assert response["status"] == 0
      assert response["action"] == expected_msg
    end

    test "command handler can read from session" do
      payload = %{
        module: Module6,
        name: :my_command_accessing_session,
        params: %{},
        target: "my_target_1"
      }

      parsed_json =
        payload
        |> serialize_payload()
        |> Jason.decode!()

      conn =
        :post
        |> conn_with_parsed_json("/hologram/command", parsed_json, %{
          "my_session_key" => :action_from_session,
          @csrf_token_session_key => @unmasked_csrf_token
        })
        |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
        |> handle_command_request()

      response = Jason.decode!(conn.resp_body)

      assert response["action"] ==
               ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("action_from_session")], [Type.atom("params"), Type.map([])], [Type.atom("target"), Type.bitstring("my_target_1")]])'
    end

    test "command handler can read from cookies" do
      payload = %{
        module: Module6,
        name: :my_command_accessing_cookie,
        params: %{},
        target: "my_target_1"
      }

      parsed_json =
        payload
        |> serialize_payload()
        |> Jason.decode!()

      encoded_cookie_value = Cookie.encode(:action_from_cookie)

      conn =
        :post
        |> conn_with_parsed_json("/hologram/command", parsed_json)
        |> Map.put(:req_headers, [
          {"cookie", "my_cookie_name=#{encoded_cookie_value}"},
          {"x-csrf-token", @masked_csrf_token}
        ])
        |> handle_command_request()

      response = Jason.decode!(conn.resp_body)

      assert response["action"] ==
               ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("action_from_cookie")], [Type.atom("params"), Type.map([])], [Type.atom("target"), Type.bitstring("my_target_1")]])'
    end

    test "command handler can write to session" do
      payload = %{
        module: Module6,
        name: :my_command_with_session,
        params: %{},
        target: "my_target_1"
      }

      conn = execute_command_request(payload)

      assert Map.has_key?(conn.private.plug_session, "my_session_key")
    end

    test "command handler can write cookies" do
      payload = %{
        module: Module6,
        name: :my_command_with_cookies,
        params: %{},
        target: "my_target_1"
      }

      conn = execute_command_request(payload)

      assert Map.has_key?(conn.resp_cookies, "my_cookie_name")
    end

    test "command handler works correctly when no session changes are made" do
      payload = %{
        module: Module6,
        name: :my_command_without_session,
        params: %{},
        target: "my_target_1"
      }

      conn = execute_command_request(payload)
      response = Jason.decode!(conn.resp_body)

      assert %{"status" => 1} = response

      # Only framework-managed entries should be in the session
      # (no app-level session entries since the command made no changes).
      assert conn.private.plug_session
             |> Map.keys()
             |> Enum.sort() == Enum.sort([@csrf_token_session_key, "hologram_session_id"])
    end

    test "command handler works correctly when no cookie changes are made" do
      payload = %{
        module: Module6,
        name: :my_command_without_cookies,
        params: %{},
        target: "my_target_1"
      }

      parsed_json =
        payload
        |> serialize_payload()
        |> Jason.decode!()

      conn =
        :post
        |> conn_with_parsed_json("/hologram/command", parsed_json)
        |> Map.put(:req_headers, [
          {"cookie", "my_cookie=cookie_value"},
          {"x-csrf-token", @masked_csrf_token}
        ])
        |> handle_command_request()

      response = Jason.decode!(conn.resp_body)

      assert %{"status" => 1} = response

      # TODO: uncomment when standalone Hologram is supported
      # Only the session cookie should be set, no additional cookies from the command
      cookie_keys = Map.keys(conn.resp_cookies)

      assert Enum.empty?(cookie_keys)
      # assert length(cookie_keys) == 1
      # assert "hologram_session" in cookie_keys
    end

    test "fires broadcasts queued during command after successful return" do
      instance_id = subscribe_to_identity_channel(:instance)

      payload = %{
        instance_id: instance_id,
        module: Module6,
        name: :my_command_queueing_broadcast,
        params: %{},
        target: "my_target_1"
      }

      execute_command_request(payload)

      assert_receive {:broadcast_action, _channel, :my_broadcast_action, %{text: "hi"},
                      [{:instance, ^instance_id}]}
    end

    test "does not fire broadcasts when command raises" do
      instance_id = subscribe_to_identity_channel(:instance)

      payload = %{
        instance_id: instance_id,
        module: Module6,
        name: :my_command_queueing_broadcast_then_raising,
        params: %{},
        target: "my_target_1"
      }

      parsed_json =
        payload
        |> serialize_payload()
        |> Jason.decode!()

      conn =
        :post
        |> conn_with_parsed_json("/hologram/command", parsed_json)
        |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)

      assert_raise RuntimeError, "boom", fn ->
        handle_command_request(conn)
      end

      refute_receive {:broadcast_action, _channel, _action_name, _params, _excluded_identities}
    end

    test "sets the selfEchoes field to the encoded actions when any self-echoes were queued" do
      payload = %{
        module: Module6,
        name: :my_command_self_echo_put_broadcast_subscribed,
        params: %{},
        target: "my_target_1"
      }

      conn = execute_command_request(payload)

      %{"selfEchoes" => encoded_self_echoes} = Jason.decode!(conn.resp_body)

      assert encoded_self_echoes ==
               ~s'Type.list([Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("test_action")], [Type.atom("params"), Type.map([[Type.atom("text"), Type.bitstring("hi")]])], [Type.atom("target"), Type.bitstring("my_target_1")]])])'
    end

    test "sets the selfEchoes field to an empty list when no self-echoes were queued" do
      payload = %{
        module: Module6,
        name: :my_command_self_echo_put_broadcast_unsubscribed,
        params: %{},
        target: "my_target_1"
      }

      conn = execute_command_request(payload)

      %{"selfEchoes" => encoded_self_echoes} = Jason.decode!(conn.resp_body)

      assert encoded_self_echoes == "Type.list([])"
    end

    test "self-echoes reach every cid on the originating instance subscribed to the channel, not just the target" do
      # Again with no registry entry - the instance-wide echo set is derived from the
      # receipts the tab presented.
      payload = %{
        instance_id: "my-instance-id",
        module: Module6,
        name: :my_command_self_echo_broadcast_only,
        params: %{},
        sub_receipts: [
          Receipt.issue(:room_a, "my_target_1", "my-instance-id", nil),
          Receipt.issue(:room_a, "sibling", "my-instance-id", nil)
        ],
        target: "my_target_1"
      }

      conn = execute_command_request(payload)
      %{"selfEchoes" => encoded_self_echoes} = Jason.decode!(conn.resp_body)

      # The broadcast self-echoes to the target cid and the sibling cid on the
      # same instance (order is not guaranteed).
      assert String.contains?(encoded_self_echoes, ~s|Type.bitstring("my_target_1")|)
      assert String.contains?(encoded_self_echoes, ~s|Type.bitstring("sibling")|)
    end

    test "broadcasts {:identity_changed, ...} on the pre session's announce topic when the handler changes identity" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      topic = Realtime.session_announce_topic(session_id)
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      session = Map.put(@session, :hologram_session_id, session_id)

      parsed_json =
        %{
          instance_id: "my-instance-id",
          module: Module6,
          name: :my_command_changing_user_id,
          params: %{},
          target: "my_target_1"
        }
        |> serialize_payload()
        |> Jason.decode!()

      :post
      |> conn_with_parsed_json("/hologram/command", parsed_json, session)
      |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
      |> handle_command_request()

      assert_receive {:identity_changed, ^session_id, 7}
    end

    test "does not broadcast {:identity_changed, ...} when the handler leaves identity unchanged" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      topic = Realtime.session_announce_topic(session_id)
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      session = Map.put(@session, :hologram_session_id, session_id)

      parsed_json =
        %{
          instance_id: "my-instance-id",
          module: Module6,
          name: :my_command_a,
          params: %{},
          target: "my_target_1"
        }
        |> serialize_payload()
        |> Jason.decode!()

      :post
      |> conn_with_parsed_json("/hologram/command", parsed_json, session)
      |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
      |> handle_command_request()

      refute_receive {:identity_changed, _session_id, _user_id}
    end

    test "does not broadcast {:identity_changed, ...} when the handler changes identity but raises" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      topic = Realtime.session_announce_topic(session_id)
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      session = Map.put(@session, :hologram_session_id, session_id)

      parsed_json =
        %{
          instance_id: "my-instance-id",
          module: Module6,
          name: :my_command_changing_user_id_then_raising,
          params: %{},
          target: "my_target_1"
        }
        |> serialize_payload()
        |> Jason.decode!()

      assert_raise RuntimeError, "boom", fn ->
        :post
        |> conn_with_parsed_json("/hologram/command", parsed_json, session)
        |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
        |> handle_command_request()
      end

      refute_receive {:identity_changed, _session_id, _user_id}
    end

    test "broadcasts {:identity_changed, ...} on the pre session's announce topic when middleware changes identity and terminates" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      topic = Realtime.session_announce_topic(session_id)
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      session = Map.put(@session, :hologram_session_id, session_id)

      parsed_json =
        %{
          instance_id: "my-instance-id",
          module: Module27,
          name: :my_command,
          params: %{},
          target: "my_target_1"
        }
        |> serialize_payload()
        |> Jason.decode!()

      :post
      |> conn_with_parsed_json("/hologram/command", parsed_json, session)
      |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
      |> handle_command_request()

      assert_receive {:identity_changed, ^session_id, 7}
    end

    test "does not broadcast {:identity_changed, ...} when middleware terminates without changing identity" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      topic = Realtime.session_announce_topic(session_id)
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      session = Map.put(@session, :hologram_session_id, session_id)

      parsed_json =
        %{
          instance_id: "my-instance-id",
          module: Module23,
          name: :my_command,
          params: %{},
          target: "my_target_1"
        }
        |> serialize_payload()
        |> Jason.decode!()

      :post
      |> conn_with_parsed_json("/hologram/command", parsed_json, session)
      |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
      |> handle_command_request()

      refute_receive {:identity_changed, _session_id, _user_id}
    end

    test "persists the changed user_id into the session when the handler changes identity" do
      parsed_json =
        %{
          instance_id: "my-instance-id",
          module: Module6,
          name: :my_command_changing_user_id,
          params: %{},
          target: "my_target_1"
        }
        |> serialize_payload()
        |> Jason.decode!()

      conn =
        :post
        |> conn_with_parsed_json("/hologram/command", parsed_json)
        |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
        |> handle_command_request()

      assert Plug.Conn.get_session(conn, :hologram_user_id) == 7
    end

    test "leaves the session user_id untouched when the handler does not change identity" do
      session = Map.put(@session, :hologram_user_id, 7)

      parsed_json =
        %{
          instance_id: "my-instance-id",
          module: Module6,
          name: :my_command_a,
          params: %{},
          target: "my_target_1"
        }
        |> serialize_payload()
        |> Jason.decode!()

      conn =
        :post
        |> conn_with_parsed_json("/hologram/command", parsed_json, session)
        |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
        |> handle_command_request()

      assert Plug.Conn.get_session(conn, :hologram_user_id) == 7
    end

    test "passes through when the SubscriptionRegistry has no entry for the instance_id" do
      conn = execute_successful_command_request()

      assert conn.status == 200
    end

    test "passes through when the SubscriptionRegistry's identity matches the caller" do
      :ok = SubscriptionRegistry.register_connection("my-instance-id", self())
      :ok = SubscriptionRegistry.update_identity("my-instance-id", @hologram_session_id, nil)

      conn =
        execute_command_request(%{
          instance_id: "my-instance-id",
          module: Module6,
          name: :my_command_a,
          params: %{},
          target: "my_target_1"
        })

      assert conn.status == 200
    end

    test "returns 403 when the SubscriptionRegistry's session_id does not match the caller" do
      :ok = SubscriptionRegistry.register_connection("my-instance-id", self())
      :ok = SubscriptionRegistry.update_identity("my-instance-id", "other-session-id", nil)

      conn =
        execute_command_request(%{
          instance_id: "my-instance-id",
          module: Module6,
          name: :my_command_a,
          params: %{},
          target: "my_target_1"
        })

      assert conn.halted == true
      assert conn.status == 403
      assert conn.resp_body == "Forbidden"
    end

    test "returns 403 when the SubscriptionRegistry's user_id does not match the caller" do
      :ok = SubscriptionRegistry.register_connection("my-instance-id", self())

      :ok =
        SubscriptionRegistry.update_identity(
          "my-instance-id",
          @hologram_session_id,
          "some-user-id"
        )

      conn =
        execute_command_request(%{
          instance_id: "my-instance-id",
          module: Module6,
          name: :my_command_a,
          params: %{},
          target: "my_target_1"
        })

      assert conn.halted == true
      assert conn.status == 403
      assert conn.resp_body == "Forbidden"
    end
  end

  describe "handle_initial_page_request/2" do
    test "updates Plug.Conn fields related to HTTP response and halts the pipeline" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module4")
        |> Plug.Test.init_test_session(%{})
        |> handle_initial_page_request(Module4)

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 200
    end

    # TODO: uncomment when standalone Hologram is supported
    # test "initializes Hologram session" do
    #   ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

    #   conn =
    #     :get
    #     |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module4")
    #     |> handle_initial_page_request(Module4)

    #   assert Map.has_key?(conn.resp_cookies, "hologram_session")
    # end

    test "extracts and casts page params and passes them to page renderer" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module1/111/ccc/222")
        |> Plug.Test.init_test_session(%{})
        |> handle_initial_page_request(Module1)

      assert conn.resp_body == "param_aaa = 111, param_bbb = 222"
    end

    test "decodes URL-encoded params" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module11, :dummy_module_11_digest)

      # URL encoded: "hello world" -> "hello%20world", "foo/bar" -> "foo%2Fbar"
      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-controller-module11/hello%20world/foo%2Fbar")
        |> Plug.Test.init_test_session(%{})
        |> handle_initial_page_request(Module11)

      assert conn.resp_body == "param_a = hello world, param_b = foo/bar"
    end

    test "passes server struct with session to page init/3" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module9, :dummy_module_9_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-controller-module9")
        |> Plug.Test.init_test_session(%{"my_session_key" => "my_session_value"})
        |> handle_initial_page_request(Module9)

      assert conn.resp_body == "session = my_session_value"
    end

    test "passes server struct with empty subscriptions to page init/3" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module13, :dummy_module_13_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-controller-module13")
        |> Plug.Test.init_test_session(%{})
        |> handle_initial_page_request(Module13)

      assert conn.resp_body == "subscription_count = 0"
    end

    test "passes server struct with cookies to page init/3" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module2, :dummy_module_2_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-controller-module2")
        |> Plug.Test.init_test_session(%{})
        |> Map.put(:req_headers, [{"cookie", "my_cookie_name=my_cookie_value"}])
        |> handle_initial_page_request(Module2)

      assert conn.resp_body == "cookie = my_cookie_value"
    end

    test "passes to renderer the initial_page? opt set to true" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module5, :dummy_module_5_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module5")
        |> Plug.Test.init_test_session(%{})
        |> handle_initial_page_request(Module5)

      # Initial pages include runtime script
      assert String.contains?(conn.resp_body, "hologram/runtime")
    end

    test "generates and includes CSRF token for initial page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module4")
        |> Plug.Test.init_test_session(%{})
        |> handle_initial_page_request(Module4)

      # Should have a CSRF token in the session
      csrf_token = Plug.Conn.get_session(conn, @csrf_token_session_key)
      assert is_binary(csrf_token)
      assert byte_size(csrf_token) == 24
    end

    test "generates and embeds instance_id for initial page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module5, :dummy_module_5_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module5")
        |> Plug.Test.init_test_session(%{})
        |> handle_initial_page_request(Module5)

      assert {:ok, _info} =
               conn.resp_body
               |> extract_instance_id()
               |> UUID.info()
    end

    test "generates a fresh instance_id on each initial page request" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module5, :dummy_module_5_digest)

      conn_1 =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module5")
        |> Plug.Test.init_test_session(%{})
        |> handle_initial_page_request(Module5)

      conn_2 =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module5")
        |> Plug.Test.init_test_session(%{})
        |> handle_initial_page_request(Module5)

      assert extract_instance_id(conn_1.resp_body) != extract_instance_id(conn_2.resp_body)
    end

    test "updates Plug.Conn session" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module10, :dummy_module_10_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-controller-module10")
        |> Plug.Test.init_test_session(%{})
        |> handle_initial_page_request(Module10)

      assert Map.has_key?(conn.private.plug_session, "my_session_key")
    end

    test "establishes a Hologram session ID" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module4")
        |> Plug.Test.init_test_session(%{})
        |> handle_initial_page_request(Module4)

      session_id = Session.get_session_id(conn)

      assert {:ok, _info} = UUID.info(session_id)
    end

    test "updates Plug.Conn cookies" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module3, :dummy_module_3_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-controller-module3")
        |> Plug.Test.init_test_session(%{})
        |> handle_initial_page_request(Module3)

      assert Map.has_key?(conn.resp_cookies, "my_cookie_name")
    end

    test "fires broadcasts queued during page init after successful render" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module12, :dummy_module_12_digest)

      topic = Realtime.identity_topic(:user, "test-broadcast-user")
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      :get
      |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module12")
      |> Plug.Test.init_test_session(%{})
      |> handle_initial_page_request(Module12)

      assert_receive {:broadcast_action, _channel, :page_init_broadcast, %{text: "hi"},
                      [{:instance, _instance_id}]}
    end
  end

  describe "handle_page_request/4" do
    # handle_page_request/4 is exposed as `@doc false` public solely as a test
    # seam: tests can drive a render with a known instance_id without going
    # through the auto-generating handle_initial_page_request/2 wrapper. Its
    # behavior is otherwise covered implicitly through the public wrappers'
    # tests (handle_initial_page_request/2, handle_subsequent_page_request/2).
    # The tests below assert the subscription-wiring and cid-binding slices.

    setup do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module14, :dummy_module_14_digest)
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module15, :dummy_module_15_digest)
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module18, :dummy_module_18_digest)
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module19, :dummy_module_19_digest)
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module20, :dummy_module_20_digest)
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module21, :dummy_module_21_digest)
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module22, :dummy_module_22_digest)
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module26, :dummy_module_26_digest)

      :ok
    end

    test "skips the render and sends the terminal response when page middleware terminates" do
      conn = render_page_with_instance(Module25, "test-instance-id")

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 403
    end

    test "runs middleware before the render and passes the enriched server" do
      conn = render_page_with_instance(Module26, "test-instance-id")

      assert String.contains?(conn.resp_body, "marker=injected_by_middleware")
    end

    test "runs page middleware as the session user" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module35, :dummy_module_35_digest)

      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{
          hologram_user_id: "019ff5c2-0000-7000-8000-000000000002"
        })
        |> Plug.Conn.fetch_cookies()
        |> handle_page_request(Module35, %{}, [],
          initial_page?: true,
          instance_id: "test-instance-id",
          csrf_token: @masked_csrf_token,
          replica_id: @replica_id,
          replica_token: @replica_token
        )

      assert String.contains?(conn.resp_body, "actor=019ff5c2-0000-7000-8000-000000000002")
    end

    test "asks the connection to replace its bindings with the page's accumulated subscriptions" do
      topic = Realtime.instance_announce_topic("test-instance-id")
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      render_page_with_instance(Module14, "test-instance-id")

      assert_receive {:replace_subscriptions, new_sub_keys, nil}

      assert {:room_page, "page"} in new_sub_keys
      assert {:room_layout, "layout"} in new_sub_keys
      assert {:room_component, "my_component"} in new_sub_keys
    end

    test "asks for no replacement when init/3 raises" do
      topic = Realtime.instance_announce_topic("raising-instance-id")
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      assert_raise RuntimeError, "boom", fn ->
        render_page_with_instance(Module15, "raising-instance-id")
      end

      refute_receive {:replace_subscriptions, _new_sub_keys, _authorizing_user_id}
    end

    test "substitutes the self_echoes placeholder in the rendered HTML" do
      :ok = SubscriptionRegistry.register_connection("test-instance-id", self())

      conn = render_page_with_instance(Module14, "test-instance-id")

      refute String.contains?(conn.resp_body, "$SELF_ECHOES_JS_PLACEHOLDER")
      assert String.contains?(conn.resp_body, "selfEchoes: Type.list([])")
    end

    test "substitutes the sub_receipt_drops placeholder with each client-claimed key the new page no longer puts" do
      :ok = SubscriptionRegistry.register_connection("test-instance-id", self())

      # Module14 puts {:room_page, "page"}, {:room_layout, "layout"},
      # {:room_component, "my_component"}. The client claims two stale bindings
      # that aren't in the new set, so transition's drop_keys contains both.
      conn =
        render_page_with_instance(Module14, "test-instance-id", [
          {:room_dropped_a, "page"},
          {:room_dropped_b, "layout"}
        ])

      refute String.contains?(conn.resp_body, "$SUB_RECEIPT_DROPS_JS_PLACEHOLDER")
      assert String.contains?(conn.resp_body, ~s'Type.atom("room_dropped_a")')
      assert String.contains?(conn.resp_body, ~s'Type.atom("room_dropped_b")')
    end

    test "substitutes the sub_receipt_adds placeholder with a receipt for each binding put during init/3" do
      :ok = SubscriptionRegistry.register_connection("test-instance-id", self())

      conn = render_page_with_instance(Module14, "test-instance-id")

      refute String.contains?(conn.resp_body, "$SUB_RECEIPT_ADDS_JS_PLACEHOLDER")
      assert String.contains?(conn.resp_body, ~s'Type.atom("room_page")')
      assert String.contains?(conn.resp_body, ~s'Type.atom("room_layout")')
      assert String.contains?(conn.resp_body, ~s'Type.atom("room_component")')
    end

    test "framework sets server.cid to \"page\" during page init/3" do
      conn = render_page_with_instance(Module18, "test-instance-id")

      assert String.contains?(conn.resp_body, "observed_cid=page")
    end

    test "delete_subscription during page init/3 cancels a prior put_subscription before transition" do
      :ok = SubscriptionRegistry.register_connection("test-instance-id", self())

      render_page_with_instance(Module19, "test-instance-id")

      bindings = SubscriptionRegistry.bindings_of("test-instance-id")

      refute Map.has_key?(bindings, {:room_a, "page"})
    end

    test "keeps a shared layout binding in both envelopes across a same-layout navigation" do
      topic = Realtime.instance_announce_topic("test-instance-id")
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      # Page 1 (Module14) - its layout Module16 puts :room_layout.
      render_page_with_instance(Module14, "test-instance-id")

      assert_receive {:replace_subscriptions, first_keys, nil}
      assert {:room_layout, "layout"} in first_keys

      # Page 2 (Module20) reuses that same layout, so the layout's binding is declared
      # again rather than dropped. Asking for it on both sides is what lets the holder
      # skip the zero-crossing - see replace_bindings/3 for that half.
      render_page_with_instance(Module20, "test-instance-id")

      assert_receive {:replace_subscriptions, second_keys, nil}
      assert {:room_layout, "layout"} in second_keys
    end

    test "treats client-claimed keys as advisory so a lying client cannot manufacture subscriptions" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

      topic = Realtime.instance_announce_topic("test-instance-id")
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      # Client claims a fake key that the server never issued. Module4's
      # init/3 puts no subscriptions.
      render_page_with_instance(Module4, "test-instance-id", [
        {:fake_room, "page"}
      ])

      # The fake key never reaches the connection - the declared set comes from init/3
      # only, not from the client's claimed list.
      assert_receive {:replace_subscriptions, [], nil}
    end

    test "broadcasts {:identity_changed, ...} on the pre session's announce topic when init/3 changes identity" do
      :ok = SubscriptionRegistry.register_connection("test-instance-id", self())

      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      topic = Realtime.session_announce_topic(session_id)
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      :get
      |> Plug.Test.conn("/")
      |> Plug.Test.init_test_session(%{hologram_session_id: session_id})
      |> Plug.Conn.fetch_cookies()
      |> handle_page_request(Module21, %{}, [],
        initial_page?: true,
        instance_id: "test-instance-id",
        csrf_token: @masked_csrf_token,
        replica_id: @replica_id,
        replica_token: @replica_token
      )

      assert_receive {:identity_changed, ^session_id, 7}
    end

    test "does not broadcast {:identity_changed, ...} when init/3 leaves identity unchanged" do
      :ok = SubscriptionRegistry.register_connection("test-instance-id", self())

      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      topic = Realtime.session_announce_topic(session_id)
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      :get
      |> Plug.Test.conn("/")
      |> Plug.Test.init_test_session(%{hologram_session_id: session_id})
      |> Plug.Conn.fetch_cookies()
      |> handle_page_request(Module14, %{}, [],
        initial_page?: true,
        instance_id: "test-instance-id",
        csrf_token: @masked_csrf_token,
        replica_id: @replica_id,
        replica_token: @replica_token
      )

      refute_receive {:identity_changed, _session_id, _user_id}
    end

    test "does not broadcast {:identity_changed, ...} when init/3 changes identity but raises" do
      :ok = SubscriptionRegistry.register_connection("test-instance-id", self())

      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      topic = Realtime.session_announce_topic(session_id)
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      assert_raise RuntimeError, "boom", fn ->
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{hologram_session_id: session_id})
        |> Plug.Conn.fetch_cookies()
        |> handle_page_request(Module22, %{}, [],
          initial_page?: true,
          instance_id: "test-instance-id",
          csrf_token: @masked_csrf_token,
          replica_id: @replica_id,
          replica_token: @replica_token
        )
      end

      refute_receive {:identity_changed, _session_id, _user_id}
    end

    test "broadcasts {:identity_changed, ...} on the pre session's announce topic when page middleware changes identity and terminates" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      topic = Realtime.session_announce_topic(session_id)
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      :get
      |> Plug.Test.conn("/")
      |> Plug.Test.init_test_session(%{hologram_session_id: session_id})
      |> Plug.Conn.fetch_cookies()
      |> handle_page_request(Module28, %{}, [],
        initial_page?: true,
        instance_id: "test-instance-id",
        csrf_token: @masked_csrf_token,
        replica_id: @replica_id,
        replica_token: @replica_token
      )

      assert_receive {:identity_changed, ^session_id, 7}
    end

    test "does not broadcast {:identity_changed, ...} when page middleware terminates without changing identity" do
      session_id = "test-session-#{:erlang.unique_integer([:positive])}"
      topic = Realtime.session_announce_topic(session_id)
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      :get
      |> Plug.Test.conn("/")
      |> Plug.Test.init_test_session(%{hologram_session_id: session_id})
      |> Plug.Conn.fetch_cookies()
      |> handle_page_request(Module25, %{}, [],
        initial_page?: true,
        instance_id: "test-instance-id",
        csrf_token: @masked_csrf_token,
        replica_id: @replica_id,
        replica_token: @replica_token
      )

      refute_receive {:identity_changed, _session_id, _user_id}
    end

    test "persists the changed user_id into the session when init/3 changes identity" do
      :ok = SubscriptionRegistry.register_connection("test-instance-id", self())

      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{hologram_session_id: "test-session-id"})
        |> Plug.Conn.fetch_cookies()
        |> handle_page_request(Module21, %{}, [],
          initial_page?: true,
          instance_id: "test-instance-id",
          csrf_token: @masked_csrf_token,
          replica_id: @replica_id,
          replica_token: @replica_token
        )

      assert Plug.Conn.get_session(conn, :hologram_user_id) == 7
    end

    test "leaves the session user_id untouched when init/3 does not change identity" do
      :ok = SubscriptionRegistry.register_connection("test-instance-id", self())

      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{
          hologram_session_id: "test-session-id",
          hologram_user_id: 7
        })
        |> Plug.Conn.fetch_cookies()
        |> handle_page_request(Module14, %{}, [],
          initial_page?: true,
          instance_id: "test-instance-id",
          csrf_token: @masked_csrf_token,
          replica_id: @replica_id,
          replica_token: @replica_token
        )

      assert Plug.Conn.get_session(conn, :hologram_user_id) == 7
    end
  end

  describe "handle_ping_request/1" do
    test "returns pong" do
      conn =
        :get
        |> Plug.Test.conn("/hologram/ping")
        |> handle_ping_request()

      assert conn.halted == true
      assert conn.resp_body == "pong"
      assert conn.state == :sent
      assert conn.status == 200

      assert {"content-type", "text/plain; charset=utf-8"} in conn.resp_headers
    end
  end

  describe "handle_sse_handshake_request/1" do
    setup do
      wait_for_process_cleanup(Handshake)
      start_supervised!(Handshake)

      wait_for_process_cleanup(Tombstone)
      start_supervised!(Tombstone)

      :ok
    end

    test "accepts the POST and returns a freshly minted handshake_id" do
      conn = post_handshake("test-instance-id", %{hologram_session_id: "test-session-id"})

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 200

      assert {:ok, %{"handshakeId" => handshake_id}} = Jason.decode(conn.resp_body)
      assert {:ok, _info} = UUID.info(handshake_id)
    end

    test "returns 401 when the session has no Hologram session_id" do
      conn = post_handshake("test-instance-id", %{})

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 401
      assert conn.resp_body == "Unauthorized"
    end

    test "stashes the handshake with empty bindings under the minted id and the identity tuple" do
      conn =
        post_handshake("test-instance-id", %{
          hologram_session_id: "test-session-id",
          hologram_user_id: "test-user-id"
        })

      {:ok, %{"handshakeId" => handshake_id}} = Jason.decode(conn.resp_body)

      assert [
               {^handshake_id, [], "test-instance-id", "test-session-id", "test-user-id",
                _expires_at}
             ] = :ets.lookup(Handshake.ets_table_name(), handshake_id)
    end

    test "collects the binding from a receipt with a valid signature" do
      receipt_token = Receipt.issue(:room_a, "page", "test-instance-id", "test-user-id")

      conn =
        post_handshake(
          "test-instance-id",
          %{hologram_session_id: "test-session-id", hologram_user_id: "test-user-id"},
          [receipt_token]
        )

      {:ok, %{"handshakeId" => handshake_id}} = Jason.decode(conn.resp_body)

      assert [
               {^handshake_id, [{{:room_a, "page"}, "test-user-id"}], _instance_id, _session_id,
                _user_id, _expires_at}
             ] = :ets.lookup(Handshake.ets_table_name(), handshake_id)
    end

    test "drops a receipt with a forged signature while keeping a valid one" do
      valid_token = Receipt.issue(:room_a, "page", "test-instance-id", "test-user-id")
      forged_token = "forged-token-not-a-valid-signature"

      conn =
        post_handshake(
          "test-instance-id",
          %{hologram_session_id: "test-session-id", hologram_user_id: "test-user-id"},
          [forged_token, valid_token]
        )

      {:ok, %{"handshakeId" => handshake_id}} = Jason.decode(conn.resp_body)

      assert [
               {^handshake_id, [{{:room_a, "page"}, "test-user-id"}], _instance_id, _session_id,
                _user_id, _expires_at}
             ] = :ets.lookup(Handshake.ets_table_name(), handshake_id)
    end

    test "stashes empty bindings when every receipt has an invalid signature" do
      conn =
        post_handshake(
          "test-instance-id",
          %{hologram_session_id: "test-session-id"},
          ["forged-1", "forged-2"]
        )

      {:ok, %{"handshakeId" => handshake_id}} = Jason.decode(conn.resp_body)

      assert [{^handshake_id, [], _instance_id, _session_id, _user_id, _expires_at}] =
               :ets.lookup(Handshake.ets_table_name(), handshake_id)
    end

    test "drops a receipt whose signed instance_id does not match the request's" do
      receipt_token = Receipt.issue(:room_a, "page", "other-instance-id", "test-user-id")

      conn =
        post_handshake(
          "test-instance-id",
          %{hologram_session_id: "test-session-id", hologram_user_id: "test-user-id"},
          [receipt_token]
        )

      {:ok, %{"handshakeId" => handshake_id}} = Jason.decode(conn.resp_body)

      assert [{^handshake_id, [], _instance_id, _session_id, _user_id, _expires_at}] =
               :ets.lookup(Handshake.ets_table_name(), handshake_id)
    end

    test "accepts an anonymous-signed receipt for an anonymous connection" do
      receipt_token = Receipt.issue(:room_a, "page", "test-instance-id", nil)

      conn =
        post_handshake(
          "test-instance-id",
          %{hologram_session_id: "test-session-id"},
          [receipt_token]
        )

      {:ok, %{"handshakeId" => handshake_id}} = Jason.decode(conn.resp_body)

      assert [
               {^handshake_id, [{{:room_a, "page"}, nil}], _instance_id, _session_id, _user_id,
                _expires_at}
             ] = :ets.lookup(Handshake.ets_table_name(), handshake_id)
    end

    test "accepts an anonymous-signed receipt for an authenticated connection (elevation)" do
      receipt_token = Receipt.issue(:room_a, "page", "test-instance-id", nil)

      conn =
        post_handshake(
          "test-instance-id",
          %{hologram_session_id: "test-session-id", hologram_user_id: "test-user-id"},
          [receipt_token]
        )

      {:ok, %{"handshakeId" => handshake_id}} = Jason.decode(conn.resp_body)

      assert [
               {^handshake_id, [{{:room_a, "page"}, nil}], _instance_id, _session_id, _user_id,
                _expires_at}
             ] = :ets.lookup(Handshake.ets_table_name(), handshake_id)
    end

    test "drops a receipt signed for a different user_id than the connection's" do
      receipt_token = Receipt.issue(:room_a, "page", "test-instance-id", "other-user-id")

      conn =
        post_handshake(
          "test-instance-id",
          %{hologram_session_id: "test-session-id", hologram_user_id: "test-user-id"},
          [receipt_token]
        )

      {:ok, %{"handshakeId" => handshake_id}} = Jason.decode(conn.resp_body)

      assert [{^handshake_id, [], _instance_id, _session_id, _user_id, _expires_at}] =
               :ets.lookup(Handshake.ets_table_name(), handshake_id)
    end

    test "drops a user-signed receipt when the connection is anonymous (de-elevation)" do
      receipt_token = Receipt.issue(:room_a, "page", "test-instance-id", "test-user-id")

      conn =
        post_handshake(
          "test-instance-id",
          %{hologram_session_id: "test-session-id"},
          [receipt_token]
        )

      {:ok, %{"handshakeId" => handshake_id}} = Jason.decode(conn.resp_body)

      assert [{^handshake_id, [], _instance_id, _session_id, _user_id, _expires_at}] =
               :ets.lookup(Handshake.ets_table_name(), handshake_id)
    end

    test "wires refreshedReceipts into the response body" do
      receipt_token = Receipt.issue(:room_a, "page", "test-instance-id", "test-user-id")

      conn =
        post_handshake(
          "test-instance-id",
          %{hologram_session_id: "test-session-id", hologram_user_id: "test-user-id"},
          [receipt_token]
        )

      %{"refreshedReceipts" => encoded} = Jason.decode!(conn.resp_body)

      assert String.contains?(encoded, ~s'Type.atom("room_a")')
      assert String.contains?(encoded, ~s'Type.bitstring("page")')
    end
  end

  describe "handle_subsequent_page_request/2" do
    setup do
      stub_page_module_resolver([Module4])
    end

    test "answers with the page described as data and halts the pipeline" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module4"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module4)

      response = Jason.decode!(conn.resp_body)

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 200

      assert response["type"] == "page"
      assert response["pageDigest"] == "dummy_module_4_digest"

      # The fixture's template is empty and its layout is a bare slot, so the render is empty too.
      # That the tree arrives as data rather than as source is what matters here; the tests that
      # follow cover what a non-empty one carries.
      assert response["tree"] == []
    end

    test "casts page params and carries them in the payload" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module1?aaa=111&bbb=222"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module1)

      response = Jason.decode!(conn.resp_body)

      # The page renders its params, so the tree carrying the render shows them cast: an uncast
      # param would be inspected as a string.
      tree_json = Jason.encode!(response["tree"])

      assert tree_json =~ "param_aaa = 111"
      assert tree_json =~ "param_bbb = 222"
    end

    test "carries the render as a tree holding no mount data script" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module5, :dummy_module_5_digest)

      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module5"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module5)

      response = Jason.decode!(conn.resp_body)

      tree_json = Jason.encode!(response["tree"])

      assert tree_json =~ "Module5 page"

      # The state travels beside the tree, so the script that would have carried it is not
      # rendered on this path at all - which is also why no placeholder can survive into it.
      refute tree_json =~ "pageMountData"
      refute tree_json =~ "JS_PLACEHOLDER"
    end

    test "marks a page payload as page data" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module4"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module4)

      assert Plug.Conn.get_resp_header(conn, "hologram-page-data") == ["true"]
    end

    # A redirect cannot survive the trip: the fetch this answers either follows it out of sight or
    # is refused its Location. So it travels as data, naming the page the client should ask for.
    test "describes a redirecting middleware's target as data" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module29, :dummy_module_29_digest)

      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module29"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module29)

      response = Jason.decode!(conn.resp_body)

      assert conn.status == 200
      assert Plug.Conn.get_resp_header(conn, "hologram-page-data") == ["true"]

      assert response["type"] == "redirect"
      assert response["to"] == Module4.__route__()
      assert response["pageModule"] == Encoder.encode_term!(Module4)
    end

    # The redirect itself cannot survive the trip, but a header set alongside it was meant for the
    # response, and the HTML path keeps it.
    test "keeps a header the redirecting middleware set" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module31, :dummy_module_31_digest)

      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module31"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module31)

      assert Plug.Conn.get_resp_header(conn, "x-my-header") == ["my_value"]
      assert Jason.decode!(conn.resp_body)["type"] == "redirect"
    end

    # The payload names where the client is going, so a location header on this 200 would name
    # somewhere it is not.
    test "does not send the redirect's location header" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module29, :dummy_module_29_digest)

      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module29"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module29)

      assert Plug.Conn.get_resp_header(conn, "location") == []
    end

    # A dead end rather than a navigation: sent as it stands, so the client can hand the path to the
    # browser and get what a typed-in URL would have given, and so logs and proxies see the denial.
    test "sends a denying middleware's response as it stands" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module25, :dummy_module_25_digest)

      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module25"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module25)

      assert conn.status == 403
      assert Plug.Conn.get_resp_header(conn, "hologram-page-data") == []
    end

    # Status alone cannot tell a page payload from a page's own answer, which is what the marker
    # header is for.
    test "sends a terminal 200 from middleware without marking it as page data" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module30, :dummy_module_30_digest)

      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module30"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module30)

      assert conn.status == 200
      assert conn.resp_body == "answered by middleware"
      assert Plug.Conn.get_resp_header(conn, "hologram-page-data") == []
    end

    test "applies the cookie operations the run accumulated" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module3, :dummy_module_3_digest)

      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module3"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module3)

      assert Map.has_key?(conn.resp_cookies, "my_cookie_name")
    end

    test "establishes a Hologram session ID" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module4"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module4)

      session_id = Session.get_session_id(conn)

      assert {:ok, _info} = UUID.info(session_id)
    end

    test "decodes URL-encoded query params" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module11, :dummy_module_11_digest)

      # URL encoded: "hello world" -> "hello%20world", "foo/bar" -> "foo%2Fbar"
      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module11?param_a=hello%20world&param_b=foo%2Fbar"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module11)

      response = Jason.decode!(conn.resp_body)

      tree_json = Jason.encode!(response["tree"])

      assert tree_json =~ "hello world"
      assert tree_json =~ "foo/bar"
    end

    test "updates Plug.Conn session" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module10, :dummy_module_10_digest)

      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module10"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module10)

      assert Map.has_key?(conn.private.plug_session, "my_session_key")
    end

    # A navigation is not where a CSRF token is minted: the page it navigates from already carries
    # one.
    test "does not generate a CSRF token" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

      conn =
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module4"
        |> subsequent_page_request_conn()
        |> handle_subsequent_page_request(Module4)

      assert is_nil(Plug.Conn.get_session(conn, @csrf_token_session_key))
    end

    test "addresses the replacement to the instance named in the request body" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

      topic = Realtime.instance_announce_topic("test-instance-id")
      Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

      # Client claims it currently holds {:room_a, "page"}. Module4 declares none, so the
      # replacement empties the set.
      body = page_request_body("test-instance-id", [{:room_a, "page"}])

      :post
      |> Plug.Test.conn(
        "/hologram/page/Hologram.Test.Fixtures.Controller.Module4",
        ""
      )
      |> Plug.Test.init_test_session(%{})
      |> Map.put(:body_params, %{"_json" => body})
      |> handle_subsequent_page_request(Module4)

      assert_receive {:replace_subscriptions, [], nil}
    end
  end

  describe "send_response/2" do
    setup do
      [conn: Plug.Test.conn(:get, "/")]
    end

    test "sends the status and body", %{conn: conn} do
      server = %Server{status: 201, response_body: "created"}
      result = send_response(conn, server)

      assert result.status == 201
      assert result.resp_body == "created"
      assert result.state == :sent
    end

    test "sends an empty body when the response body is nil", %{conn: conn} do
      server = %Server{status: 204}
      result = send_response(conn, server)

      assert result.status == 204
      assert result.resp_body == ""
    end

    test "merges response headers onto existing ones", %{conn: conn} do
      conn = Plug.Conn.put_resp_header(conn, "x-existing", "kept")
      server = %Server{status: 200, response_headers: %{"x-custom" => "1"}}
      result = send_response(conn, server)

      assert Plug.Conn.get_resp_header(result, "x-existing") == ["kept"]
      assert Plug.Conn.get_resp_header(result, "x-custom") == ["1"]
    end
  end

  describe "verify_and_refresh_receipts/4" do
    setup do
      wait_for_process_cleanup(Tombstone)
      start_supervised!(Tombstone)

      :ok
    end

    test "refreshes the created_at on a passing receipt" do
      original_token = Receipt.issue(:room_a, "page", "test-instance-id", "test-user-id")
      {:ok, %Receipt{created_at: original_created_at}} = Receipt.verify(original_token)

      Process.sleep(1)

      {_bindings, refreshed} =
        verify_and_refresh_receipts(
          [original_token],
          "test-instance-id",
          "test-session-id",
          "test-user-id"
        )

      assert [{:room_a, "page", fresh_token}] = refreshed

      {:ok, %Receipt{created_at: refreshed_created_at}} = Receipt.verify(fresh_token)

      assert refreshed_created_at > original_created_at
    end

    test "omits failed receipts from the refreshed list" do
      valid_token = Receipt.issue(:room_a, "page", "test-instance-id", "test-user-id")
      forged_token = "forged-token-not-a-valid-signature"

      {_bindings, refreshed} =
        verify_and_refresh_receipts(
          [forged_token, valid_token],
          "test-instance-id",
          "test-session-id",
          "test-user-id"
        )

      assert [{:room_a, "page", _fresh_token}] = refreshed
    end

    test "rejects a receipt when a binding-level user tombstone exists at or after the receipt's created_at" do
      token = Receipt.issue(:room_a, "page", "test-instance-id", "test-user-id")
      {:ok, %Receipt{created_at: receipt_created_at}} = Receipt.verify(token)

      Tombstone.insert({{:user, "test-user-id"}, :room_a, "page"}, receipt_created_at + 1)

      {bindings, refreshed} =
        verify_and_refresh_receipts(
          [token],
          "test-instance-id",
          "test-session-id",
          "test-user-id"
        )

      assert bindings == []
      assert refreshed == []
    end

    test "rejects a receipt when a channel-wide session tombstone exists at or after the receipt's created_at" do
      token = Receipt.issue(:room_a, "page", "test-instance-id", "test-user-id")
      {:ok, %Receipt{created_at: receipt_created_at}} = Receipt.verify(token)

      Tombstone.insert({{:session, "test-session-id"}, :room_a}, receipt_created_at + 1)

      {bindings, refreshed} =
        verify_and_refresh_receipts(
          [token],
          "test-instance-id",
          "test-session-id",
          "test-user-id"
        )

      assert bindings == []
      assert refreshed == []
    end

    test "skips nil identity levels when checking tombstones" do
      token = Receipt.issue(:room_a, "page", "test-instance-id", "test-user-id")

      {_bindings, refreshed} =
        verify_and_refresh_receipts([token], "test-instance-id", nil, "test-user-id")

      assert [{:room_a, "page", _fresh_token}] = refreshed
    end

    test "passes a post-unsub receipt whose created_at is greater than the tombstone's" do
      token = Receipt.issue(:room_a, "page", "test-instance-id", "test-user-id")
      {:ok, %Receipt{created_at: receipt_created_at}} = Receipt.verify(token)

      Tombstone.insert({{:user, "test-user-id"}, :room_a, "page"}, receipt_created_at - 1)

      {_bindings, refreshed} =
        verify_and_refresh_receipts(
          [token],
          "test-instance-id",
          "test-session-id",
          "test-user-id"
        )

      assert [{:room_a, "page", _fresh_token}] = refreshed
    end

    test "applies tombstone check to elevated (anonymous-authorized) receipts" do
      token = Receipt.issue(:room_a, "page", "test-instance-id", nil)
      {:ok, %Receipt{created_at: receipt_created_at}} = Receipt.verify(token)

      Tombstone.insert({{:instance, "test-instance-id"}, :room_a, "page"}, receipt_created_at + 1)

      {bindings, refreshed} =
        verify_and_refresh_receipts(
          [token],
          "test-instance-id",
          "test-session-id",
          "test-user-id"
        )

      assert bindings == []
      assert refreshed == []
    end
  end
end
