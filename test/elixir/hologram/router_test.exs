defmodule Hologram.RouterTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Router
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Test.Fixtures.Router.Module1

  use_module_stub :page_digest_registry
  use_module_stub :page_module_resolver

  setup :set_mox_global

  setup do
    System.put_env(
      "SECRET_KEY_BASE",
      "test_secret_key_base_that_is_long_enough_for_testing_purposes_in_hologram"
    )

    setup_page_digest_registry(PageDigestRegistryStub)
    setup_page_module_resolver(PageModuleResolverStub)
  end

  describe "call/2" do
    test "request path is matched" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn =
        :get
        |> Plug.Test.conn("/hologram-test-fixtures-router-module1")
        |> Plug.Conn.fetch_cookies()
        |> call([])

      assert conn.halted == true
      assert conn.resp_body == "page Hologram.Test.Fixtures.Router.Module1 template"
      assert conn.state == :sent
      assert conn.status == 200
    end

    test "request path is not matched" do
      conn =
        :get
        |> Plug.Test.conn("/my-unmatched-request-path")
        |> Plug.Conn.fetch_cookies()
        |> call([])

      assert conn.halted == false
      assert conn.resp_body == nil
      assert conn.state == :unset
      assert conn.status == nil
    end
  end
end
