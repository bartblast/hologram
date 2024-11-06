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
    setup_page_digest_registry(PageDigestRegistryStub)
    setup_page_module_resolver(PageModuleResolverStub)
  end

  describe "call/2" do
    test "request path is matched" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module1, :dummy_module_1_digest)

      conn = Plug.Test.conn(:get, "/hologram-test-fixtures-router-module1")

      assert call(conn, []) == %{
               conn
               | halted: true,
                 resp_body: "page Hologram.Test.Fixtures.Router.Module1 template",
                 resp_headers: [
                   {"content-type", "text/html; charset=utf-8"},
                   {"cache-control", "max-age=0, private, must-revalidate"}
                 ],
                 state: :sent,
                 status: 200
             }
    end

    test "request path is not matched" do
      conn = Plug.Test.conn(:get, "/my-unmatched-request-path")

      assert call(conn, []) == %{
               conn
               | halted: false,
                 resp_body: nil,
                 resp_headers: [{"cache-control", "max-age=0, private, must-revalidate"}],
                 state: :unset,
                 status: nil
             }
    end
  end
end
