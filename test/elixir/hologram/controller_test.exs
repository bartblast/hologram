defmodule Hologram.ControllerTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Controller
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Runtime.Cookie
  alias Hologram.Test.Fixtures.Controller.Module1
  alias Hologram.Test.Fixtures.Controller.Module2
  alias Hologram.Test.Fixtures.Controller.Module3
  alias Hologram.Test.Fixtures.Controller.Module4
  alias Hologram.Test.Fixtures.Controller.Module5

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry
  use_module_stub :server

  setup :set_mox_global

  @timestamp 1_752_074_624_726_958

  test "extract_params/2" do
    url_path = "/hologram-test-fixtures-runtime-controller-module1/111/ccc/222"

    assert extract_params(url_path, Module1) == %{"aaa" => "111", "bbb" => "222"}
  end

  describe "apply_cookie_ops/2" do
    setup do
      [conn: Plug.Test.conn(:get, "/")]
    end

    test "applies put operation with default cookie opts", %{conn: conn} do
      cookie_struct = %Cookie{value: "test_value"}
      cookie_ops = %{"test_cookie" => {:put, @timestamp, cookie_struct}}

      updated_conn = apply_cookie_ops(conn, cookie_ops)

      assert updated_conn.resp_cookies == %{
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

      cookie_ops = %{"test_cookie" => {:put, @timestamp, cookie_struct}}

      updated_conn = apply_cookie_ops(conn, cookie_ops)

      assert updated_conn.resp_cookies == %{
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
      cookie_ops = %{"existing_cookie" => {:delete, @timestamp}}

      updated_conn = apply_cookie_ops(conn, cookie_ops)

      assert updated_conn.resp_cookies == %{
               "existing_cookie" => %{universal_time: {{1970, 1, 1}, {0, 0, 0}}, max_age: 0}
             }
    end

    test "applies multiple operations", %{conn: conn} do
      cookie_struct_1 = %Cookie{value: "new_value_1", path: "/path-1"}
      cookie_struct_2 = %Cookie{value: "new_value_2", path: "/path-2"}

      cookie_ops = %{
        "new_cookie_1" => {:put, @timestamp + 1, cookie_struct_1},
        "new_cookie_2" => {:put, @timestamp + 2, cookie_struct_2},
        "old_cookie" => {:delete, @timestamp + 3}
      }

      updated_conn = apply_cookie_ops(conn, cookie_ops)

      # Check new cookies are set
      assert updated_conn.resp_cookies["new_cookie_1"][:value]
      assert updated_conn.resp_cookies["new_cookie_2"][:value]

      # Check old cookie is deleted
      assert updated_conn.resp_cookies["old_cookie"] == %{
               universal_time: {{1970, 1, 1}, {0, 0, 0}},
               max_age: 0
             }
    end

    test "handles empty cookie operations", %{conn: conn} do
      cookie_ops = %{}

      updated_conn = apply_cookie_ops(conn, cookie_ops)

      assert updated_conn.resp_cookies == %{}
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

      cookie_ops = %{"test_cookie" => {:put, @timestamp, cookie_struct}}

      updated_conn = apply_cookie_ops(conn, cookie_ops)

      cookie_data = updated_conn.resp_cookies["test_cookie"]

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

  describe "handle_initial_page_request/2" do
    setup do
      setup_page_digest_registry(PageDigestRegistryStub)
      setup_server(ServerStub)
    end

    test "updates Plug.Conn fields related to HTTP response and halts the pipeline" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module4")
        |> handle_initial_page_request(Module4)

      assert conn.halted == true
      assert conn.state == :sent
      assert conn.status == 200
    end

    test "initializes Hologram session" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module4, :dummy_module_4_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module4")
        |> handle_initial_page_request(Module4)

      assert Map.has_key?(conn.resp_cookies, "hologram_session")
    end

    test "extracts and casts page params and passes them to page renderer" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module1/111/ccc/222")
        |> handle_initial_page_request(Module1)

      assert conn.resp_body == "param_aaa = 111, param_bbb = 222"
    end

    test "builds server struct with cookies and passes it to page renderer" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module2, :dummy_module_2_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-controller-module2")
        |> Map.put(:req_headers, [{"cookie", "my_cookie=cookie_value"}])
        |> handle_initial_page_request(Module2)

      assert conn.resp_body == "cookie = cookie_value"
    end

    test "passes to renderer the initial_page? opt set to true" do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_asset_manifest_cache(AssetManifestCacheStub)

      ETS.put(PageDigestRegistryStub.ets_table_name(), Module5, :dummy_module_5_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module5")
        |> handle_initial_page_request(Module5)

      # Initial pages include runtime script
      assert String.contains?(conn.resp_body, "hologram/runtime")
    end

    test "updates Plug.Conn cookies" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module3, :dummy_module_3_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-controller-module3")
        |> handle_initial_page_request(Module3)

      assert Map.has_key?(conn.resp_cookies, "my_cookie")
    end
  end
end
