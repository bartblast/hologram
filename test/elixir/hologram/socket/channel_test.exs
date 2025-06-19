defmodule Hologram.Socket.ChannelTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Socket.Channel
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Test.Fixtures.Socket.Channel.Module2
  alias Hologram.Test.Fixtures.Socket.Channel.Module3
  alias Hologram.Test.Fixtures.Socket.Channel.Module5

  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry

  setup :set_mox_global

  describe "handle_in/3, page" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_page_digest_registry(PageDigestRegistryStub)
    end

    test "module payload" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module2, :dummy_module_2_digest)

      payload = [2, "aElixir.Hologram.Test.Fixtures.Socket.Channel.Module2"]

      assert handle_in("page", payload, :dummy_socket) ==
               {:reply, {:ok, "page Module2 template"}, :dummy_socket}
    end

    test "tuple payload" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module3, :dummy_module_3_digest)

      payload = [
        2,
        %{
          "t" => "t",
          "d" => [
            "aElixir.Hologram.Test.Fixtures.Socket.Channel.Module3",
            %{
              "t" => "m",
              "d" => [
                ["aa", "i1"],
                ["ab", "i2"]
              ]
            }
          ]
        }
      ]

      assert handle_in("page", payload, :dummy_socket) ==
               {:reply, {:ok, "page Module3 template, params: a = 1, b = 2"}, :dummy_socket}
    end

    test "rendered page is not treated as initial page" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module5, :dummy_module_5_digest)

      payload = [2, "aElixir.Hologram.Test.Fixtures.Socket.Channel.Module5"]

      assert {:reply, {:ok, html}, :dummy_socket} = handle_in("page", payload, :dummy_socket)

      refute String.contains?(html, "__hologramAssetManifest__")
    end
  end

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
