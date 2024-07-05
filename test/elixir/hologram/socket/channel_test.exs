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
      payload = %{
        "type" => "map",
        "data" => [
          [
            %{"type" => "atom", "value" => "module"},
            %{"type" => "atom", "value" => "Elixir.Hologram.Test.Fixtures.Socket.Channel.Module1"}
          ],
          [
            %{"type" => "atom", "value" => "name"},
            %{"type" => "atom", "value" => "my_command_a"}
          ],
          [%{"type" => "atom", "value" => "params"}, %{"type" => "map", "data" => []}],
          [%{"type" => "atom", "value" => "target"}, "__binary__:my_target_1"]
        ]
      }

      assert handle_in("command", payload, :dummy_socket) ==
               {:reply, {:ok, ~s/Type.atom("nil")/}, :dummy_socket}
    end

    test "next action with target not specified" do
      payload = %{
        "type" => "map",
        "data" => [
          [
            %{"type" => "atom", "value" => "module"},
            %{"type" => "atom", "value" => "Elixir.Hologram.Test.Fixtures.Socket.Channel.Module1"}
          ],
          [
            %{"type" => "atom", "value" => "name"},
            %{"type" => "atom", "value" => "my_command_b"}
          ],
          [
            %{"type" => "atom", "value" => "params"},
            %{
              "type" => "map",
              "data" => [
                [%{"type" => "atom", "value" => "a"}, "__integer__:1"],
                [%{"type" => "atom", "value" => "b"}, "__integer__:2"]
              ]
            }
          ],
          [%{"type" => "atom", "value" => "target"}, "__binary__:my_target_1"]
        ]
      }

      assert handle_in("command", payload, :dummy_socket) ==
               {:reply,
                {:ok,
                 ~s/Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("name"), Type.atom("my_action_b")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring("my_target_1")]])/},
                :dummy_socket}
    end

    test "next action with target specified" do
      payload = %{
        "type" => "map",
        "data" => [
          [
            %{"type" => "atom", "value" => "module"},
            %{"type" => "atom", "value" => "Elixir.Hologram.Test.Fixtures.Socket.Channel.Module1"}
          ],
          [
            %{"type" => "atom", "value" => "name"},
            %{"type" => "atom", "value" => "my_command_c"}
          ],
          [
            %{"type" => "atom", "value" => "params"},
            %{
              "type" => "map",
              "data" => [
                [%{"type" => "atom", "value" => "a"}, "__integer__:1"],
                [%{"type" => "atom", "value" => "b"}, "__integer__:2"]
              ]
            }
          ],
          [%{"type" => "atom", "value" => "target"}, "__binary__:my_target_1"]
        ]
      }

      assert handle_in("command", payload, :dummy_socket) ==
               {:reply,
                {:ok,
                 ~s/Type.map([[Type.atom("__struct__"), Type.atom("Elixir.Hologram.Component.Action")], [Type.atom("name"), Type.atom("my_action_c")], [Type.atom("params"), Type.map([[Type.atom("c"), Type.integer(3n)]])], [Type.atom("target"), Type.bitstring("my_target_2")]])/},
                :dummy_socket}
    end

    test "next action params contain an anonymous function that is not a named function capture" do
      payload = %{
        "type" => "map",
        "data" => [
          [
            %{"type" => "atom", "value" => "module"},
            %{"type" => "atom", "value" => "Elixir.Hologram.Test.Fixtures.Socket.Channel.Module6"}
          ],
          [
            %{"type" => "atom", "value" => "name"},
            %{"type" => "atom", "value" => "my_command_6"}
          ],
          [
            %{"type" => "atom", "value" => "params"},
            %{
              "type" => "map",
              "data" => []
            }
          ],
          [%{"type" => "atom", "value" => "target"}, "__binary__:my_target_1"]
        ]
      }

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
      stub_with(PageDigestRegistryMock, PageDigestRegistryStub)
      stub_with(AssetPathRegistryMock, AssetPathRegistryStub)

      setup_asset_fixtures(AssetPathRegistryStub.static_dir())
      AssetPathRegistry.start_link([])
      AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

      setup_page_digest_registry(PageDigestRegistryStub)

      :ok
    end

    test "module payload" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module2, :dummy_module_2_digest)

      payload = %{
        "type" => "atom",
        "value" => "Elixir.Hologram.Test.Fixtures.Socket.Channel.Module2"
      }

      assert handle_in("page", payload, :dummy_socket) ==
               {:reply, {:ok, "page Module2 template"}, :dummy_socket}
    end

    test "tuple payload" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module3, :dummy_module_3_digest)

      payload = %{
        "type" => "tuple",
        "data" => [
          %{"type" => "atom", "value" => "Elixir.Hologram.Test.Fixtures.Socket.Channel.Module3"},
          %{
            "type" => "map",
            "data" => [
              [%{"type" => "atom", "value" => "a"}, "__integer__:1"],
              [%{"type" => "atom", "value" => "b"}, "__integer__:2"]
            ]
          }
        ]
      }

      assert handle_in("page", payload, :dummy_socket) ==
               {:reply, {:ok, "page Module3 template, params: a = 1, b = 2"}, :dummy_socket}
    end

    test "rendered page is not treated as initial page" do
      ETS.put(PageDigestRegistryStub.ets_table_name(), Module5, :dummy_module_5_digest)

      payload = %{
        "type" => "atom",
        "value" => "Elixir.Hologram.Test.Fixtures.Socket.Channel.Module5"
      }

      assert {:reply, {:ok, html}, :dummy_socket} = handle_in("page", payload, :dummy_socket)

      refute String.contains?(html, "__hologramAssetManifest__")
    end
  end

  describe "join/3" do
    test "valid topic name" do
      assert join("hologram", :dummy_payload, :dummy_socket) == {:ok, :dummy_socket}
    end

    test "invalid topic name" do
      assert_raise FunctionClauseError,
                   "no function clause matching in Hologram.Socket.Channel.join/3",
                   fn ->
                     join("invalid", :dummy_payload, :dummy_socket)
                   end
    end
  end
end
