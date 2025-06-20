defmodule Hologram.Socket.ChannelTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Socket.Channel
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Test.Fixtures.Socket.Channel.Module2

  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry

  setup :set_mox_global

  test "handle_in/3, page_bundle_path" do
    setup_page_digest_registry(PageDigestRegistryStub)
    ETS.put(PageDigestRegistryStub.ets_table_name(), Module2, "12345678901234567890123456789012")

    payload = [2, "aElixir.Hologram.Test.Fixtures.Socket.Channel.Module2"]

    assert handle_in("page_bundle_path", payload, :dummy_socket) ==
             {:reply, {:ok, "/hologram/page-12345678901234567890123456789012.js"}, :dummy_socket}
  end

  describe "join/3" do
    test "valid topic name" do
      assert join("hologram", :dummy_payload, :dummy_socket) == {:ok, :dummy_socket}
    end

    test "invalid topic name" do
      assert_raise FunctionClauseError,
                   build_function_clause_error_msg("Hologram.Socket.Channel.join/3"),
                   fn ->
                     join("invalid", :dummy_payload, :dummy_socket)
                   end
    end
  end
end
