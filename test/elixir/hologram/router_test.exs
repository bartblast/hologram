defmodule Hologram.RouterTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Router

  alias Hologram.Commons.PLT
  alias Hologram.Router.PageResolver
  alias Hologram.Test.Fixtures.Router.Module1

  describe "call/2" do
    setup do
      opts = setup_page_digest_lookup(__MODULE__)

      page_resolver_store_key = random_atom()
      PageResolver.start_link(store_key: page_resolver_store_key)

      Keyword.put(opts, :page_resolver_store_key, page_resolver_store_key)
    end

    test "request path is matched", opts do
      PLT.put(opts[:page_digest_lookup_plt], Module1, :dummy_module_1_digest)

      conn = Plug.Test.conn(:get, "/hologram-test-fixtures-router-module1")

      assert call(conn, opts) == %{
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

    test "request path is not matched", opts do
      conn = Plug.Test.conn(:get, "/my-unmatched-request-path")

      assert call(conn, opts) == %{
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
