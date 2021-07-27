defmodule Hologram.Runtime.ChannelTest do
  use Hologram.ChannelCase, async: true
  alias Hologram.Compiler.Serializer

  setup do
    {:ok, _, socket} =
      socket(Socket)
      |> subscribe_and_join(Channel, "hologram")

    {:ok, socket: socket}
  end

  test "command without params that returns action without params", %{socket: socket} do
    page_module = "Elixir_Hologram_Test_Fixtures_Runtime_Module1"

    message =
      %{
        command: "test_command",
        context: %{"page_module" => page_module, "scope_module" => page_module},
        params: %{}
      }

    expected_response = Serializer.serialize({:test_action, %{}})

    ref = push(socket, "command", message)
    assert_reply ref, :ok, expected_response
  end

  test "command without params that returns action with params", %{socket: socket} do
    page_module = "Elixir_Hologram_Test_Fixtures_Runtime_Module3"

    message =
      %{
        command: "test_command",
        context: %{"page_module" => page_module, "scope_module" => page_module},
        params: %{}
      }

    expected_response = Serializer.serialize({:test_action, %{a: 1, b: 2}})

    ref = push(socket, "command", message)
    assert_reply ref, :ok, expected_response
  end

  test "command with params that returns action without params", %{socket: socket} do
    page_module = "Elixir_Hologram_Test_Fixtures_Runtime_Module4"

    message =
      %{
        command: "test_command",
        context: %{"page_module" => page_module, "scope_module" => page_module},
        params: %{"a" => 1, "b" => 2}
      }

    expected_response = Serializer.serialize({:test_action_1, %{}})

    ref = push(socket, "command", message)
    assert_reply ref, :ok, expected_response
  end

  test "command with params that returns action with params", %{socket: socket} do
    page_module = "Elixir_Hologram_Test_Fixtures_Runtime_Module2"

    message =
      %{
        command: "test_command",
        context: %{"page_module" => page_module, "scope_module" => page_module},
        params: %{"a" => 1, "b" => 2}
      }

    expected_response = Serializer.serialize({:test_action, %{a: 10, b: 20}})

    ref = push(socket, "command", message)
    assert_reply ref, :ok, expected_response
  end
end
