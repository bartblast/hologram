defmodule Hologram.Runtime.MessageHandlerTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Commons.SystemUtils
  alias Hologram.Runtime.CookieStore
  alias Hologram.Runtime.MessageHandler
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module1
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module2
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module3
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module5
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module6
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module7
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module8
  alias Hologram.Test.Fixtures.Runtime.MessageHandler.Module9

  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry
  use_module_stub :server

  setup :set_mox_global

  setup do
    setup_server(ServerStub)

    [connection_state: %{cookie_store: %CookieStore{}, plug_conn: %Plug.Conn{}}]
  end

  # Make sure String.to_existing_atom/1 recognizes atoms from the fixture component
  Code.ensure_loaded(Module1)
  Code.ensure_loaded(Module6)
  Code.ensure_loaded(Module7)
  Code.ensure_loaded(Module8)
  Code.ensure_loaded(Module9)

  describe "handle/3, command" do
    test "next action is nil", %{connection_state: connection_state} do
      payload = %{
        module: Module1,
        name: :my_command_a,
        params: %{},
        target: "my_target_1"
      }

      assert MessageHandler.handle("command", payload, connection_state) ==
               {"reply", [1, ~s'Type.atom("nil")', 0], connection_state}
    end

    test "next action with target not specified", %{connection_state: connection_state} do
      payload = %{
        module: Module1,
        name: :my_command_b,
        params: %{a: 1, b: 2},
        target: "my_target_1"
      }

      assert MessageHandler.handle("command", payload, connection_state) ==
               {"reply",
                [
                  1,
                  ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("name"), Type.atom("my_action_b")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring("my_target_1")]])',
                  0
                ], connection_state}
    end

    test "next action with target specified", %{connection_state: connection_state} do
      payload = %{
        module: Module1,
        name: :my_command_c,
        params: %{a: 1, b: 2},
        target: "my_target_1"
      }

      assert MessageHandler.handle("command", payload, connection_state) ==
               {"reply",
                [
                  1,
                  ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("name"), Type.atom("my_action_c")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring("my_target_2")]])',
                  0
                ], connection_state}
    end

    test "next action params contain an anonymous function that is not a named function capture",
         %{connection_state: connection_state} do
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

      assert MessageHandler.handle("command", payload, connection_state) ==
               {"reply", [0, expected_msg, 0], connection_state}
    end

    test "command handler can read from cookie store", %{
      connection_state: connection_state_fixture
    } do
      payload = %{
        module: Module1,
        name: :my_command_accessing_cookie,
        params: %{},
        target: "my_target_1"
      }

      connection_state = %{
        connection_state_fixture
        | cookie_store: %CookieStore{persisted: %{"my_cookie" => {:nop, 0, :action_from_cookie}}}
      }

      {"reply", [1, encoded_action, 0], ^connection_state} =
        MessageHandler.handle("command", payload, connection_state)

      assert encoded_action ==
               ~s'Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("name"), Type.atom("action_from_cookie")], [Type.atom("params"), Type.map([])], [Type.atom("target"), Type.bitstring("my_target_1")]])'
    end

    test "command handler can write to cookie store", %{connection_state: connection_state} do
      payload = %{
        module: Module1,
        name: :my_command_with_cookies,
        params: %{},
        target: "my_target_1"
      }

      {"reply", [1, _next_action, 1], new_connection_state} =
        MessageHandler.handle("command", payload, connection_state)

      assert CookieStore.has_pending_ops?(new_connection_state.cookie_store)
    end

    test "command handler works correctly when cookie store is not read from or written to", %{
      connection_state: connection_state
    } do
      payload = %{
        module: Module1,
        name: :my_command_without_cookies,
        params: %{},
        target: "my_target_1"
      }

      {"reply", [1, _next_action, 0], ^connection_state} =
        MessageHandler.handle("command", payload, connection_state)

      refute CookieStore.has_pending_ops?(connection_state.cookie_store)
    end
  end

  describe "handle/3, page" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_page_digest_registry(PageDigestRegistryStub)
    end

    test "module payload", %{connection_state: connection_state} do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module2, :dummy_module_2_digest)

      assert MessageHandler.handle("page", Module2, connection_state) ==
               {"reply", "page Module2 template", connection_state}
    end

    test "tuple payload", %{connection_state: connection_state} do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module3, :dummy_module_3_digest)

      payload = {Module3, %{a: 1, b: 2}}

      assert MessageHandler.handle("page", payload, connection_state) ==
               {"reply", "page Module3 template, params: a = 1, b = 2", connection_state}
    end

    test "rendered page is not treated as initial page", %{connection_state: connection_state} do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module5, :dummy_module_5_digest)

      assert {"reply", html, _new_connection_state} =
               MessageHandler.handle("page", Module5, connection_state)

      refute String.contains?(html, "__hologramAssetManifest__")
    end

    test "command handler can read from cookie store", %{
      connection_state: connection_state_fixture
    } do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module7, :dummy_module_7_digest)

      connection_state = %{
        connection_state_fixture
        | cookie_store: %CookieStore{persisted: %{"test_cookie" => {:nop, 0, "test_value"}}}
      }

      assert {"reply", "cookie = test_value", ^connection_state} =
               MessageHandler.handle("page", Module7, connection_state)
    end

    test "page handler can write to cookie store", %{connection_state: connection_state} do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module8, :dummy_module_8_digest)

      {"reply", _html, new_connection_state} =
        MessageHandler.handle("page", Module8, connection_state)

      assert CookieStore.has_pending_ops?(new_connection_state.cookie_store)
    end

    test "page handler works correctly when cookie store is not read from or written to", %{
      connection_state: connection_state
    } do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module9, :dummy_module_9_digest)

      {"reply", _html, ^connection_state} =
        MessageHandler.handle("page", Module9, connection_state)

      refute CookieStore.has_pending_ops?(connection_state.cookie_store)
    end
  end

  describe "handle/3, page_bundle_path" do
    test "returns page bundle path" do
      setup_page_digest_registry(PageDigestRegistryStub)

      ETS.put(
        PageDigestRegistryStub.ets_table_name(),
        Module2,
        "12345678901234567890123456789012"
      )

      assert MessageHandler.handle("page_bundle_path", Module2, %Server{}) ==
               {"reply", "/hologram/page-12345678901234567890123456789012.js"}
    end
  end
end
