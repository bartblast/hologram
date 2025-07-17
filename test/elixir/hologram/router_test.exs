defmodule Hologram.RouterTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Router
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
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
  end

  describe "/hologram/command" do
    test "routes POST command request" do
      serialized_payload =
        Jason.encode!([
          2,
          %{
            "t" => "m",
            "d" => [
              ["amodule", "a#{Module2}"],
              ["aname", "amy_command"],
              ["aparams", %{"t" => "m", "d" => []}],
              ["atarget", "b0746573745f746172676574"]
            ]
          }
        ])

      conn =
        :post
        |> Plug.Test.conn("/hologram/command", serialized_payload)
        |> call([])

      assert conn.halted == true
      assert conn.resp_body == ~s'[1,"Type.atom(\\\"nil\\\")"]'
      assert conn.state == :sent
      assert conn.status == 200
    end
  end

  describe "/hologram/page" do
    test "responds with requested page" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram/page/Hologram.Test.Fixtures.Router.Module1?a=123&b=xyz")
        |> call([])

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 200

      assert String.contains?(conn.resp_body, "Module1 page, a = 123, b = :xyz")

      # Initial pages include runtime script
      refute String.contains?(conn.resp_body, "hologram/runtime")
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
        |> call([])

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 200

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
