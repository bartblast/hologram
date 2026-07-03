defmodule Hologram.RouterTest do
  use Hologram.Test.BasicCase, async: false

  import ExUnit.CaptureLog
  import Hologram.Router
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Realtime.Handshake
  alias Hologram.Runtime.CSRFProtection
  alias Hologram.Test.Fixtures.Router.Module1
  alias Hologram.Test.Fixtures.Router.Module2

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry
  use_module_stub :page_module_resolver

  setup :set_mox_global

  setup do
    original_hologram_start_flag = System.get_env("HOLOGRAM_START")
    System.put_env("HOLOGRAM_START", "1")

    on_exit(fn ->
      if original_hologram_start_flag do
        System.put_env("HOLOGRAM_START", original_hologram_start_flag)
      else
        System.delete_env("HOLOGRAM_START")
      end
    end)

    setup_asset_path_registry(AssetPathRegistryStub)
    AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

    setup_asset_manifest_cache(AssetManifestCacheStub)

    setup_page_digest_registry(PageDigestRegistryStub)

    setup_page_module_resolver(PageModuleResolverStub)

    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(Hologram.Realtime.SubscriptionRegistry)
    start_supervised!(Hologram.Realtime.SubscriptionRegistry)

    wait_for_process_cleanup(Handshake)
    start_supervised!({Handshake, boot_sync_timeout_ms: 0})

    :ok
  end

  describe "/hologram/command" do
    test "routes POST command request" do
      {masked_csrf_token, unmasked_csrf_token} = CSRFProtection.generate_tokens()

      # Simulate that JSON has already been parsed upstream by Plug.Parsers
      parsed_json = [
        2,
        %{
          "t" => "m",
          "d" => [
            ["ainstance_id", "b074657374696e7374616e6365"],
            ["amodule", "a#{Module2}"],
            ["aname", "amy_command"],
            ["aparams", %{"t" => "m", "d" => []}],
            ["atarget", "b0746573745f746172676574"]
          ]
        }
      ]

      conn =
        :post
        |> Plug.Test.conn("/hologram/command", "")
        |> Plug.Test.init_test_session(%{CSRFProtection.session_key() => unmasked_csrf_token})
        |> Map.put(:body_params, %{"_json" => parsed_json})
        |> Plug.Conn.put_req_header("x-csrf-token", masked_csrf_token)
        |> call([])

      assert Jason.decode!(conn.resp_body) == %{
               "action" => ~s'Type.atom("nil")',
               "selfEchoes" => "Type.list([])",
               "status" => 1,
               "subReceiptAdds" => "Type.list([])",
               "subReceiptDrops" => "Type.list([])"
             }
    end
  end

  describe "/hologram/page" do
    test "routes POST subsequent page request" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      # Simulate that JSON has already been parsed upstream by Plug.Parsers
      parsed_json = [
        2,
        %{
          "t" => "m",
          "d" => [
            ["aclient_claimed_sub_keys", %{"t" => "l", "d" => []}],
            ["ainstance_id", "b074657374696e7374616e6365"]
          ]
        }
      ]

      conn =
        :post
        |> Plug.Test.conn(
          "/hologram/page/Hologram.Test.Fixtures.Router.Module1?a=123&b=xyz",
          ""
        )
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Test.init_test_session(%{})
        |> Map.put(:body_params, %{"_json" => parsed_json})
        |> call([])

      assert String.contains?(conn.resp_body, "Module1 page, a = 123, b = :xyz")

      # Initial pages include runtime script
      refute String.contains?(conn.resp_body, "hologram/runtime")
    end
  end

  describe "/hologram/ping" do
    test "routes GET ping request" do
      conn =
        :get
        |> Plug.Test.conn("/hologram/ping")
        |> call([])

      assert conn.resp_body == "pong"
    end
  end

  describe "/hologram/sse" do
    test "returns 401 when no Hologram session ID is present" do
      conn =
        :get
        |> Plug.Test.conn("/hologram/sse")
        |> Plug.Test.init_test_session(%{})
        |> call([])

      assert conn.halted == true
      assert conn.status == 401
      assert conn.resp_body == "Unauthorized"
    end

    test "opens an SSE stream when a Hologram session ID is present" do
      instance_id = "test-instance-id"
      session_id = "some-session-id"
      handshake_id = "test-handshake-#{:erlang.unique_integer([:positive])}"

      Handshake.insert(
        handshake_id,
        [],
        {instance_id, session_id, nil},
        System.system_time(:millisecond) + Handshake.stash_ttl_ms()
      )

      conn =
        :get
        |> Plug.Test.conn("/hologram/sse?instance_id=#{instance_id}&handshake_id=#{handshake_id}")
        |> Plug.Test.init_test_session(%{hologram_session_id: session_id})

      # SSE.stream/1 blocks in a receive loop forever; run it in a Task so the
      # test process can drive it, then send {:close, _reason} to terminate the
      # loop cleanly and await the final conn for assertions.
      task = Task.async(fn -> call(conn, []) end)
      Process.sleep(50)
      send(task.pid, {:close, :test_done})
      result_conn = Task.await(task)

      assert result_conn.status == 200
      assert result_conn.state == :chunked

      # The conn must be halted so the endpoint pipeline does not fall through to a
      # host router after the stream closes. Without it, the committed response is
      # re-dispatched and surfaces as a masked Plug.Conn.AlreadySentError.
      assert result_conn.halted == true

      assert result_conn.resp_headers == [
               {"cache-control", "no-cache"},
               {"connection", "keep-alive"},
               {"content-type", "text/event-stream"}
             ]
    end
  end

  describe "/hologram/websocket" do
    test "upgrades websocket connection" do
      conn =
        :get
        |> Plug.Test.conn("/hologram/websocket")
        |> Map.put(:req_headers, [
          {"host", "localhost"},
          {"upgrade", "websocket"},
          {"connection", "Upgrade"},
          {"sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ=="},
          {"sec-websocket-version", "13"}
        ])
        |> call([])

      assert conn.halted == true
      assert conn.state == :upgraded
      assert conn.status == 101
    end
  end

  describe "catch-all route" do
    test "request path is matched" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-router-module1/123/xyz")
        |> Plug.Test.init_test_session(%{})
        |> call([])

      assert String.contains?(conn.resp_body, "Module1 page, a = 123, b = :xyz")

      # Initial pages include runtime script
      assert String.contains?(conn.resp_body, "hologram/runtime")
    end

    test "request path is not matched" do
      conn =
        :get
        |> Plug.Test.conn("/my-unmatched-request-path")
        |> call([])

      assert conn.halted == false
      assert conn.resp_body == nil
      assert conn.state == :unset
      assert conn.status == nil
    end
  end

  describe "when Hologram is disabled" do
    setup do
      System.delete_env("HOLOGRAM_START")
      :ok
    end

    test "passes the connection through for a path that would match a Hologram page" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-router-module1/123/xyz")
        |> Plug.Test.init_test_session(%{})
        |> call([])

      assert conn.halted == false
      assert conn.resp_body == nil
      assert conn.state == :unset
      assert conn.status == nil
    end

    test "passes the connection through for a framework route the router would otherwise handle" do
      # POST /hologram/command is a real Hologram route. Sent without a valid
      # CSRF token it is rejected with 403, which proves the route is actually
      # defined and handled by the router. An undefined path would fall through
      # to the catch-all and pass through regardless of whether the connection
      # is short-circuited - so this guards against the route being removed and
      # the assertions below silently becoming meaningless.
      build_conn = fn ->
        :post
        |> Plug.Test.conn("/hologram/command", "")
        |> Plug.Test.init_test_session(%{})
      end

      # Enabled: the router handles the route.
      System.put_env("HOLOGRAM_START", "1")
      {handled_conn, _log} = with_log(fn -> call(build_conn.(), []) end)

      assert handled_conn.halted == true
      assert handled_conn.status == 403

      # Disabled: the router steps aside, leaving the connection untouched for
      # the next plug.
      System.delete_env("HOLOGRAM_START")
      passed_through_conn = call(build_conn.(), [])

      assert passed_through_conn.halted == false
      assert passed_through_conn.resp_body == nil
      assert passed_through_conn.state == :unset
      assert passed_through_conn.status == nil
    end
  end
end
