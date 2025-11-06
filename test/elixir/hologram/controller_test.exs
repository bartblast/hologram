defmodule Hologram.ControllerTest do
  use Hologram.Test.BasicCase, async: false

  import ExUnit.CaptureLog
  import Hologram.Controller
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Commons.SystemUtils
  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.CSRFProtection
  alias Hologram.Test.Fixtures.Controller.Module1
  alias Hologram.Test.Fixtures.Controller.Module10
  alias Hologram.Test.Fixtures.Controller.Module11
  alias Hologram.Test.Fixtures.Controller.Module2
  alias Hologram.Test.Fixtures.Controller.Module3
  alias Hologram.Test.Fixtures.Controller.Module4
  alias Hologram.Test.Fixtures.Controller.Module5
  alias Hologram.Test.Fixtures.Controller.Module6
  alias Hologram.Test.Fixtures.Controller.Module8
  alias Hologram.Test.Fixtures.Controller.Module9

  @unmasked_csrf_token CSRFProtection.generate_unmasked_token()
  @masked_csrf_token CSRFProtection.get_masked_token(@unmasked_csrf_token)

  @csrf_token_session_key CSRFProtection.session_key()
  @session %{@csrf_token_session_key => @unmasked_csrf_token}

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry

  setup :set_mox_global

  # Create a test connection with parsed JSON body_params (simulating what Plug.Parsers does)
  defp conn_with_parsed_json(method, path, parsed_json, session \\ @session) do
    method
    |> Plug.Test.conn(path, "")
    |> Plug.Test.init_test_session(session)
    |> Map.put(:body_params, %{"_json" => parsed_json})
  end

  defp execute_successful_command_request do
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

    :post
    |> conn_with_parsed_json("/hologram/command", parsed_json)
    |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
    |> handle_command_request()
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
    target_hex =
      payload.target
      |> :binary.bin_to_list()
      |> Enum.map(&Integer.to_string(&1, 16))
      |> Enum.map(&String.downcase/1)
      |> Enum.map_join(&String.pad_leading(&1, 2, "0"))

    serialized_map_data = [
      ["amodule", "a#{payload.module}"],
      ["aname", "a#{payload.name}"],
      ["aparams", serialize_params(payload.params)],
      ["atarget", "b0#{target_hex}"]
    ]

    Jason.encode!([2, %{"t" => "m", "d" => serialized_map_data}])
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

  describe "handle_command_request/1" do
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
      assert response == [1, ~s'Type.atom("nil")']
    end

    test "updates Plug.Conn fields related to HTTP response and halts the pipeline when CSRF token validation succeeds" do
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
        |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
        |> handle_command_request()

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
      assert response == [1, ~s'Type.atom("nil")']
    end

    test "command with next action target not specified" do
      payload = %{
        module: Module6,
        name: :my_command_b,
        params: %{a: 1, b: 2},
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
        |> handle_command_request()

      response = Jason.decode!(conn.resp_body)

      assert response == [
               1,
               ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("my_action_b")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring("my_target_1")]])'
             ]
    end

    test "command with next action target specified" do
      payload = %{
        module: Module6,
        name: :my_command_c,
        params: %{a: 1, b: 2},
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
        |> handle_command_request()

      response = Jason.decode!(conn.resp_body)

      assert response == [
               1,
               ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("my_action_c")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring("my_target_2")]])'
             ]
    end

    test "command with encoding error for anonymous function" do
      payload = %{
        module: Module8,
        name: :my_command_8,
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
        |> handle_command_request()

      response = Jason.decode!(conn.resp_body)

      expected_msg =
        if SystemUtils.otp_version() >= 23 do
          "term contains a function that is not a named function capture"
        else
          "term contains a function that is not a remote function capture"
        end

      assert response == [0, expected_msg]
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

      assert response == [
               1,
               ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("action_from_session")], [Type.atom("params"), Type.map([])], [Type.atom("target"), Type.bitstring("my_target_1")]])'
             ]
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

      assert response == [
               1,
               ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("delay"), Type.integer(0n)], [Type.atom("name"), Type.atom("action_from_cookie")], [Type.atom("params"), Type.map([])], [Type.atom("target"), Type.bitstring("my_target_1")]])'
             ]
    end

    test "command handler can write to session" do
      payload = %{
        module: Module6,
        name: :my_command_with_session,
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
        |> handle_command_request()

      assert Map.has_key?(conn.private.plug_session, "my_session_key")
    end

    test "command handler can write cookies" do
      payload = %{
        module: Module6,
        name: :my_command_with_cookies,
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
        |> handle_command_request()

      assert Map.has_key?(conn.resp_cookies, "my_cookie_name")
    end

    test "command handler works correctly when no session changes are made" do
      payload = %{
        module: Module6,
        name: :my_command_without_session,
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
        |> handle_command_request()

      response = Jason.decode!(conn.resp_body)
      assert [1, _encoded_action] = response

      # Only the CSRF token should be in the session
      assert Map.keys(conn.private.plug_session) == [@csrf_token_session_key]
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
      assert [1, _encoded_action] = response

      # TODO: uncomment when standalone Hologram is supported
      # Only the session cookie should be set, no additional cookies from the command
      cookie_keys = Map.keys(conn.resp_cookies)
      assert Enum.empty?(cookie_keys)
      # assert length(cookie_keys) == 1
      # assert "hologram_session" in cookie_keys
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

    test "passes server struct with session to page renderer" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module9, :dummy_module_9_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-controller-module9")
        |> Plug.Test.init_test_session(%{"my_session_key" => "my_session_value"})
        |> handle_initial_page_request(Module9)

      assert conn.resp_body == "session = my_session_value"
    end

    test "passes server struct with cookies to page renderer" do
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

    test "updates Plug.Conn session" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module10, :dummy_module_10_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-controller-module10")
        |> Plug.Test.init_test_session(%{})
        |> handle_initial_page_request(Module10)

      assert Map.has_key?(conn.private.plug_session, "my_session_key")
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

  describe "handle_subsequent_page_request/3" do
    test "updates Plug.Conn fields related to HTTP response and halts the pipeline" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram/page/Hologram.Test.Fixtures.Controller.Module4")
        |> Plug.Test.init_test_session(%{})
        |> handle_subsequent_page_request(Module4)

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 200
    end

    # TODO: uncomment when standalone Hologram is supported
    # test "initializes Hologram session" do
    #   ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

    #   conn =
    #     :get
    #     |> Plug.Test.conn("/hologram/page/Hologram.Test.Fixtures.Controller.Module4")
    #     |> handle_subsequent_page_request(Module4)

    #   assert Map.has_key?(conn.resp_cookies, "hologram_session")
    # end

    test "casts page params and passes them to page renderer" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn =
        :get
        |> Plug.Test.conn(
          "/hologram/page/Hologram.Test.Fixtures.Controller.Module1?aaa=111&bbb=222"
        )
        |> Plug.Test.init_test_session(%{})
        |> handle_subsequent_page_request(Module1)

      assert conn.resp_body == "param_aaa = 111, param_bbb = 222"
    end

    test "decodes URL-encoded query params" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module11, :dummy_module_11_digest)

      # URL encoded: "hello world" -> "hello%20world", "foo/bar" -> "foo%2Fbar"
      conn =
        :get
        |> Plug.Test.conn(
          "/hologram/page/Hologram.Test.Fixtures.Controller.Module11?param_a=hello%20world&param_b=foo%2Fbar"
        )
        |> Plug.Test.init_test_session(%{})
        |> handle_subsequent_page_request(Module11)

      assert conn.resp_body == "param_a = hello world, param_b = foo/bar"
    end

    test "passes server struct with session to page renderer" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module9, :dummy_module_9_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram/page/Hologram.Test.Fixtures.Controller.Module9")
        |> Plug.Test.init_test_session(%{"my_session_key" => "my_session_value"})
        |> handle_subsequent_page_request(Module9)

      assert conn.resp_body == "session = my_session_value"
    end

    test "passes server struct with cookies to page renderer" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module2, :dummy_module_2_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram/page/Hologram.Test.Fixtures.Controller.Module2")
        |> Plug.Test.init_test_session(%{})
        |> Map.put(:req_headers, [{"cookie", "my_cookie_name=my_cookie_value"}])
        |> handle_subsequent_page_request(Module2)

      assert conn.resp_body == "cookie = my_cookie_value"
    end

    test "passes to renderer the initial_page? opt set to false" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module5, :dummy_module_5_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram/page/Hologram.Test.Fixtures.Controller.Module5")
        |> Plug.Test.init_test_session(%{})
        |> handle_subsequent_page_request(Module5)

      # Initial pages include runtime script
      refute String.contains?(conn.resp_body, "hologram/runtime")
    end

    test "does not generate CSRF token for subsequent page requests" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram/page/Hologram.Test.Fixtures.Controller.Module4")
        |> Plug.Test.init_test_session(%{})
        |> handle_subsequent_page_request(Module4)

      # Should not have a CSRF token in the session for subsequent page requests
      csrf_token = Plug.Conn.get_session(conn, @csrf_token_session_key)
      assert is_nil(csrf_token)
    end

    test "updates Plug.Conn session" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module10, :dummy_module_10_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram/page/Hologram.Test.Fixtures.Controller.Module10")
        |> Plug.Test.init_test_session(%{})
        |> handle_subsequent_page_request(Module10)

      assert Map.has_key?(conn.private.plug_session, "my_session_key")
    end

    test "updates Plug.Conn cookies" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module3, :dummy_module_3_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram/page/Hologram.Test.Fixtures.Controller.Module3")
        |> Plug.Test.init_test_session(%{})
        |> handle_subsequent_page_request(Module3)

      assert Map.has_key?(conn.resp_cookies, "my_cookie_name")
    end
  end
end
