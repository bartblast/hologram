defmodule HologramE2E.ChannelTest do
  use HologramE2E.Test.ChannelCase, async: false

  alias Hologram.Compiler.Serializer
  alias Hologram.Runtime
  alias Hologram.Runtime.{Channel, Socket}
  alias Hologram.Template.Renderer

  @class_name_1 "Elixir_HologramE2E_Test_Fixtures_Runtime_Channel_Module1"
  @class_name_3 "Elixir_HologramE2E_Test_Fixtures_Runtime_Channel_Module3"
  @class_name_4 "Elixir_HologramE2E_Test_Fixtures_Runtime_Channel_Module4"
  @class_name_5 "Elixir_HologramE2E_Test_Fixtures_Runtime_Channel_Module5"
  @class_name_6 "Elixir_HologramE2E_Test_Fixtures_Runtime_Channel_Module6"
  @class_name_7 "Elixir_HologramE2E_Test_Fixtures_Runtime_Channel_Module7"

  @module_5 HologramE2E.Test.Fixtures.Runtime.Channel.Module5
  @target_id %{"type" => "atom", "value" => "test_target_id_value"}

  setup do
    {:ok, _, socket} =
      socket(Socket)
      |> subscribe_and_join(Channel, "hologram")

    {:ok, socket: socket}
  end

  defp build_message(target_module, target_id) do
    %{
      target_module: target_module,
      target_id: target_id,
      command: %{"type" => "atom", "value" => "test_command"},
      params: %{"type" => "list", data: []}
    }
  end

  test "command returning target_id, action and params", %{socket: socket} do
    target_module = %{
      "type" => "module",
      "className" => @class_name_6
    }

    message = build_message(target_module, @target_id)
    ref = push(socket, "command", message)

    expected_response =
      {:test_action_target_id, :test_action, %{a: 1, b: 2}}
      |> Serializer.serialize()

    assert_reply(ref, :ok, ^expected_response)
  end

  test "command returning target_id and action", %{socket: socket} do
    target_module = %{
      "type" => "module",
      "className" => @class_name_7
    }

    message = build_message(target_module, @target_id)
    ref = push(socket, "command", message)

    expected_response =
      {:test_action_target_id, :test_action, %{}}
      |> Serializer.serialize()

    assert_reply(ref, :ok, ^expected_response)
  end

  test "command returning action and params", %{socket: socket} do
    target_module = %{
      "type" => "module",
      "className" => @class_name_3
    }

    message = build_message(target_module, @target_id)
    ref = push(socket, "command", message)

    expected_response =
      {:test_target_id_value, :test_action, %{a: 1, b: 2}}
      |> Serializer.serialize()

    assert_reply(ref, :ok, ^expected_response)
  end

  test "command returning action only", %{socket: socket} do
    target_module = %{
      "type" => "module",
      "className" => @class_name_1
    }

    message = build_message(target_module, @target_id)
    ref = push(socket, "command", message)

    expected_response =
      {:test_target_id_value, :test_action, %{}}
      |> Serializer.serialize()

    assert_reply(ref, :ok, ^expected_response)
  end

  test "command which receives params", %{socket: socket} do
    target_module = %{
      "type" => "module",
      "className" => @class_name_4
    }

    message = %{
      target_module: target_module,
      target_id: @target_id,
      command: %{"type" => "atom", "value" => "test_command"},
      params: %{
        "type" => "list",
        "data" => [
          %{
            "type" => "tuple",
            "data" => [
              %{"type" => "atom", "value" => "a"},
              %{"type" => "integer", "value" => 1}
            ]
          },
          %{
            "type" => "tuple",
            "data" => [
              %{"type" => "atom", "value" => "b"},
              %{"type" => "integer", "value" => 2}
            ]
          }
        ]
      }
    }

    ref = push(socket, "command", message)

    expected_response =
      {:test_target_id_value, :test_action_1, %{}}
      |> Serializer.serialize()

    assert_reply(ref, :ok, ^expected_response)
  end

  test "command returning __redirect__ action", %{socket: socket} do
    "#{@fixtures_path}/runtime/channel"
    |> compile_templatables()

    Runtime.reload()

    target_module = %{
      "type" => "module",
      "className" => @class_name_5
    }

    message = %{
      target_module: target_module,
      target_id: @target_id,
      command: %{"type" => "atom", "value" => "__redirect__"},
      params: %{
        "type" => "list",
        "data" => [
          %{
            "type" => "tuple",
            "data" => [
              %{"type" => "atom", "value" => "page"},
              %{"type" => "module", "className" => @class_name_5}
            ]
          }
        ]
      }
    }

    html = Renderer.render(@module_5, %{})

    expected_response =
      {:test_target_id_value, :__redirect__, %{html: html, url: "/test-route-5"}}
      |> Serializer.serialize()

    ref = push(socket, "command", message)
    assert_reply(ref, :ok, ^expected_response)
  end
end
