defmodule Hologram.Socket.ChannelTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Socket.Channel
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS
  alias Hologram.Commons.SystemUtils
  alias Hologram.Test.Fixtures.Socket.Channel.Module2
  alias Hologram.Test.Fixtures.Socket.Channel.Module3
  alias Hologram.Test.Fixtures.Socket.Channel.Module5

  # Make sure String.to_existing_atom/1 recognizes atoms from the fixture component
  Code.ensure_loaded(Hologram.Test.Fixtures.Socket.Channel.Module1)
  Code.ensure_loaded(Hologram.Test.Fixtures.Socket.Channel.Module6)

  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry

  setup :set_mox_global

  describe "handle_in/3, command" do
    test "next action is nil" do
      payload = [
        1,
        %{
          "type" => "map",
          "data" => [
            ["a:module", "a:Elixir.Hologram.Test.Fixtures.Socket.Channel.Module1"],
            ["a:name", "a:my_command_a"],
            ["a:params", %{"t" => "m", "d" => []}],
            ["a:target", "b:6d795f7461726765745f31"]
          ]
        }
      ]

      assert handle_in("command", payload, :dummy_socket) ==
               {:reply, {:ok, ~s/Type.atom("nil")/}, :dummy_socket}
    end

    test "next action with target not specified" do
      payload = [
        1,
        %{
          "type" => "map",
          "data" => [
            ["a:module", "a:Elixir.Hologram.Test.Fixtures.Socket.Channel.Module1"],
            ["a:name", "a:my_command_b"],
            [
              "a:params",
              %{
                "type" => "map",
                "data" => [
                  ["a:a", "i:1"],
                  ["a:b", "i:2"]
                ]
              }
            ],
            ["a:target", "b:6d795f7461726765745f31"]
          ]
        }
      ]

      assert handle_in("command", payload, :dummy_socket) ==
               {:reply,
                {:ok,
                 ~s/Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("name"), Type.atom("my_action_b")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring2("my_target_1")]])/},
                :dummy_socket}
    end

    test "next action with target specified" do
      payload = [
        1,
        %{
          "type" => "m",
          "d" => [
            ["a:module", "a:Elixir.Hologram.Test.Fixtures.Socket.Channel.Module1"],
            ["a:name", "a:my_command_c"],
            [
              "a:params",
              %{
                "t" => "m",
                "d" => [
                  ["a:a", "i:1"],
                  ["a:b", "i:2"]
                ]
              }
            ],
            ["a:target", "b:6d795f7461726765745f31"]
          ]
        }
      ]

      assert handle_in("command", payload, :dummy_socket) ==
               {:reply,
                {:ok,
                 ~s/Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("name"), Type.atom("my_action_c")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring2("my_target_2")]])/},
                :dummy_socket}
    end

    test "next action params contain an anonymous function that is not a named function capture" do
      payload = [
        1,
        %{
          "t" => "m",
          "d" => [
            ["a:module", "a:Elixir.Hologram.Test.Fixtures.Socket.Channel.Module6"],
            ["a:name", "a:my_command_6"],
            ["a:params", %{"t" => "m", "d" => []}],
            ["a:target", "b:6d795f7461726765745f31"]
          ]
        }
      ]

      expected_msg =
        if SystemUtils.otp_version() >= 23 do
          "term contains an anonymous function that is not a named function capture"
        else
          "term contains an anonymous function that is not a remote function capture"
        end

      assert handle_in("command", payload, :dummy_socket) ==
               {:reply, {:error, expected_msg}, :dummy_socket}
    end
  end

  describe "handle_in/3, page" do
    setup do
      setup_asset_path_registry(AssetPathRegistryStub)
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_page_digest_registry(PageDigestRegistryStub)
    end

    test "module payload" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module2, :dummy_module_2_digest)

      payload = [1, "a:Elixir.Hologram.Test.Fixtures.Socket.Channel.Module2"]

      assert handle_in("page", payload, :dummy_socket) ==
               {:reply, {:ok, "page Module2 template"}, :dummy_socket}
    end

    test "tuple payload" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module3, :dummy_module_3_digest)

      payload = [
        1,
        %{
          "type" => "tuple",
          "data" => [
            "a:Elixir.Hologram.Test.Fixtures.Socket.Channel.Module3",
            %{
              "type" => "map",
              "data" => [
                ["a:a", "i:1"],
                ["a:b", "i:2"]
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

      payload = [1, "a:Elixir.Hologram.Test.Fixtures.Socket.Channel.Module5"]

      assert {:reply, {:ok, html}, :dummy_socket} = handle_in("page", payload, :dummy_socket)

      refute String.contains?(html, "__hologramAssetManifest__")
    end
  end

  test "handle_in/3, page_bundle_path" do
    setup_page_digest_registry(PageDigestRegistryStub)
    ETS.put(PageDigestRegistryStub.ets_table_name(), Module2, "12345678901234567890123456789012")

    payload = [1, "a:Elixir.Hologram.Test.Fixtures.Socket.Channel.Module2"]

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
