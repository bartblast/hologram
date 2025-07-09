defmodule Hologram.ControllerTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Controller
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Server.Cookie
  alias Hologram.Test.Fixtures.Controller.Module1
  alias Hologram.Test.Fixtures.Controller.Module2

  use_module_stub :page_digest_registry
  use_module_stub :server

  setup :set_mox_global

  @timestamp 1_752_074_624_726_958

  test "extract_params/2" do
    url_path = "/hologram-test-fixtures-runtime-controller-module1/111/ccc/222"

    assert extract_params(url_path, Module1) == %{aaa: "111", bbb: "222"}
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

  describe "handle_request/2" do
    setup do
      setup_page_digest_registry(PageDigestRegistryStub)
      setup_server(ServerStub)
    end

    test "conn updates" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-runtime-controller-module1/111/ccc/222")
        |> Plug.Conn.fetch_cookies()
        |> handle_request(Module1)

      assert conn.halted == true
      assert conn.resp_body == "param_aaa = 111, param_bbb = 222"
      assert conn.state == :sent
      assert conn.status == 200

      assert Map.has_key?(conn.resp_cookies, "hologram_session")
    end

    test "server struct from Server.from/1 is used for rendering" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module2, :dummy_module_2_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-controller-module2")
        |> Map.put(:req_headers, [{"cookie", "my_cookie=cookie_value"}])
        |> Plug.Conn.fetch_cookies()
        |> handle_request(Module2)

      assert conn.resp_body == "cookie = cookie_value"
    end
  end
end
