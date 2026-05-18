defmodule Hologram.RouterTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Router
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Runtime.CSRFProtection
  alias Hologram.Test.Fixtures.Router.Module1
  alias Hologram.Test.Fixtures.Router.Module2

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry
  use_module_stub :page_module_resolver

  setup :set_mox_global

  setup do
    setup_asset_path_registry(AssetPathRegistryStub)
    AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

    setup_asset_manifest_cache(AssetManifestCacheStub)

    setup_page_digest_registry(PageDigestRegistryStub)

    setup_page_module_resolver(PageModuleResolverStub)

    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(Hologram.Realtime.SubscriptionRegistry)
    start_supervised!(Hologram.Realtime.SubscriptionRegistry)

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

      assert conn.resp_body ==
               ~s'[1,"Type.atom(\\\"nil\\\")","Type.list([])","Type.list([])","Type.list([])"]'
    end
  end

  describe "/hologram/page" do
    test "routes GET subsequent page request" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram/page/Hologram.Test.Fixtures.Router.Module1?a=123&b=xyz")
        |> Plug.Test.init_test_session(%{})
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
      conn =
        :get
        |> Plug.Test.conn("/hologram/sse?instance_id=test-instance-id")
        |> Plug.Test.init_test_session(%{hologram_session_id: "some-session-id"})

      # SSE.stream/1 blocks in a receive loop forever; run it in a Task so the
      # test process can drive it, then send {:close, _reason} to terminate the
      # loop cleanly and await the final conn for assertions.
      task = Task.async(fn -> call(conn, []) end)
      Process.sleep(50)
      send(task.pid, {:close, :test_done})
      result_conn = Task.await(task)

      assert result_conn.status == 200
      assert result_conn.state == :chunked

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

      # Note: In production, WebSocket upgrades should set status to 101 (Switching Protocols),
      # but Plug.Adapters.Test.Conn.upgrade/3 doesn't simulate this HTTP protocol behavior.
      # The :upgraded state confirms the upgrade was processed correctly in the test environment.
      assert conn.status == nil
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
end
