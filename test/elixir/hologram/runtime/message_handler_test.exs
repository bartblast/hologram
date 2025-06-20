defmodule Hologram.Runtime.MessageHandlerTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Commons.SystemUtils
  alias Hologram.Runtime.MessageHandler
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module1
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module2
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module3
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module5
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module6

  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry

  setup :set_mox_global

  # Make sure String.to_existing_atom/1 recognizes atoms from the fixture component
  Code.ensure_loaded(Module1)
  Code.ensure_loaded(Module6)

  describe "handle/2, command" do
    test "next action is nil" do
      payload = %{
        module: Module1,
        name: :my_command_a,
        params: %{},
        target: "my_target_1"
      }

      assert MessageHandler.handle("command", payload) ==
               {:ok, ~s'Type.atom("nil")'}
    end

    test "next action with target not specified" do
      payload = %{
        module: Module1,
        name: :my_command_b,
        params: %{a: 1, b: 2},
        target: "my_target_1"
      }

      assert MessageHandler.handle("command", payload) ==
               {:ok,
                ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("name"), Type.atom("my_action_b")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring("my_target_1")]])'}
    end

    test "next action with target specified" do
      payload = %{
        module: Module1,
        name: :my_command_c,
        params: %{a: 1, b: 2},
        target: "my_target_1"
      }

      assert MessageHandler.handle("command", payload) ==
               {:ok,
                ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("name"), Type.atom("my_action_c")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring("my_target_2")]])'}
    end

    test "next action params contain an anonymous function that is not a named function capture" do
      payload = %{
        module: Module6,
        name: :my_command_6,
        params: %{},
        target: "my_target_1"
      }

      expected_msg =
        if SystemUtils.otp_version() >= 23 do
          "term contains a function that is not a named function capture"
        else
          "term contains a function that is not a remote function capture"
        end

      assert MessageHandler.handle("command", payload) == {:error, expected_msg}
    end
  end

  describe "handle/2, page" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_page_digest_registry(PageDigestRegistryStub)
    end

    test "module payload" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module2, :dummy_module_2_digest)

      assert MessageHandler.handle("page", Module2) ==
               {:ok, "page Module2 template"}
    end

    test "tuple payload" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module3, :dummy_module_3_digest)

      payload = {Module3, %{a: 1, b: 2}}

      assert MessageHandler.handle("page", payload) ==
               {:ok, "page Module3 template, params: a = 1, b = 2"}
    end

    test "rendered page is not treated as initial page" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module5, :dummy_module_5_digest)

      assert {:ok, html} = MessageHandler.handle("page", Module5)

      refute String.contains?(html, "__hologramAssetManifest__")
    end
  end

  describe "handle/2, page_bundle_path" do
    test "returns page bundle path" do
      setup_page_digest_registry(PageDigestRegistryStub)

      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module2,
        "12345678901234567890123456789012"
      )

      assert MessageHandler.handle("page_bundle_path", Module2) ==
               {:ok, "/hologram/page-12345678901234567890123456789012.js"}
    end
  end
end
