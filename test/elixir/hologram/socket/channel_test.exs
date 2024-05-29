defmodule Hologram.Socket.ChannelTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Socket.Channel
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Commons.ETS
  alias Hologram.Test.Fixtures.Socket.Channel.Module2
  alias Hologram.Test.Fixtures.Socket.Channel.Module3

  # Make sure String.to_existing_atom/1 recognizes atoms from the fixture component
  Code.ensure_loaded(Hologram.Test.Fixtures.Socket.Channel.Module1)

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
  end

  describe "handle_in/3, page" do
    setup do
      stub_with(PageDigestRegistryMock, PageDigestRegistryStub)
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
