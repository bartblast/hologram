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
    scope_module = "Elixir_Hologram_Test_Fixtures_Runtime_Module2"
    context = %{"page_module" => page_module, "scope_module" => scope_module}

    message =
      %{
        command: "test_command",
        context: context,
        params: %{}
      }

    ref = push(socket, "command", message)

    expected_response =
      {:test_action, %{}, context}
      |> Serializer.serialize()

    assert_reply ref, :ok, expected_response
  end

  test "command without params that returns action with params", %{socket: socket} do
    page_module = "Elixir_Hologram_Test_Fixtures_Runtime_Module3"
    scope_module = "Elixir_Hologram_Test_Fixtures_Runtime_Module2"
    context = %{"page_module" => page_module, "scope_module" => scope_module}

    message =
      %{
        command: "test_command",
        context: context,
        params: %{}
      }

    ref = push(socket, "command", message)

    expected_response =
      {:test_action, %{a: 1, b: 2}, context}
      |> Serializer.serialize()

    assert_reply ref, :ok, expected_response
  end

  test "command with params that returns action without params", %{socket: socket} do
    page_module = "Elixir_Hologram_Test_Fixtures_Runtime_Module4"
    scope_module = "Elixir_Hologram_Test_Fixtures_Runtime_Module2"
    context = %{"page_module" => page_module, "scope_module" => scope_module}

    message =
      %{
        command: "test_command",
        context: context,
        params: %{"a" => 1, "b" => 2}
      }

    ref = push(socket, "command", message)

    expected_response =
      {:test_action_1, %{}, context}
      |> Serializer.serialize()

    assert_reply ref, :ok, expected_response
  end

  test "command with params that returns action with params", %{socket: socket} do
    page_module = "Elixir_Hologram_Test_Fixtures_Runtime_Module2"
    scope_module = "Elixir_Hologram_Test_Fixtures_Runtime_Module3"
    context = %{"page_module" => page_module, "scope_module" => scope_module}

    message =
      %{
        command: "test_command",
        context: context,
        params: %{"a" => 1, "b" => 2}
      }

    ref = push(socket, "command", message)

    expected_response =
      {:test_action, %{a: 10, b: 20}, context}
      |> Serializer.serialize()

    assert_reply ref, :ok, expected_response
  end
end
