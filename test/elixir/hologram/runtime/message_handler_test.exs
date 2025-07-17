defmodule Hologram.Runtime.MessageHandlerTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Runtime.CookieStore
  alias Hologram.Runtime.MessageHandler
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module2

  use_module_stub :page_digest_registry

  setup :set_mox_global

  setup do
    [connection_state: %{cookie_store: %CookieStore{}, plug_conn: %Plug.Conn{}}]
  end

  describe "handle/3, page_bundle_path" do
    test "returns page bundle path", %{connection_state: connection_state} do
      setup_page_digest_registry(PageDigestRegistryStub)

      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module2,
        "12345678901234567890123456789012"
      )

      assert MessageHandler.handle("page_bundle_path", Module2, connection_state) ==
               {"reply", "/hologram/page-12345678901234567890123456789012.js", connection_state}
    end
  end

  describe "handle/3, ping" do
    test "returns pong reply", %{connection_state: connection_state} do
      assert MessageHandler.handle("ping", nil, connection_state) ==
               {"pong", :__no_payload__, connection_state}
    end
  end
end
