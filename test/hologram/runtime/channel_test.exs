defmodule Hologram.Runtime.ChannelTest do
  use Hologram.Test.ChannelCase, async: false

  alias Hologram.Compiler.Serializer
  alias Hologram.Runtime.{Channel, Socket}
  alias Hologram.Template.Renderer

  @class_name_1 "Elixir_Hologram_Test_Fixtures_Runtime_Channel_Module1"
  @class_name_2 "Elixir_Hologram_Test_Fixtures_Runtime_Channel_Module2"
  @class_name_3 "Elixir_Hologram_Test_Fixtures_Runtime_Channel_Module3"
  @class_name_4 "Elixir_Hologram_Test_Fixtures_Runtime_Channel_Module4"
  @class_name_5 "Elixir_Hologram_Test_Fixtures_Runtime_Channel_Module5"

  @module_5 Hologram.Test.Fixtures.Runtime.Channel.Module5
  @target_id %{"type" => "string", "value" => "test_target_id"}

  setup_all do
    on_exit(&compile_pages/0)
  end

  setup do
    {:ok, _, socket} =
      socket(Socket)
      |> subscribe_and_join(Channel, "hologram")

    {:ok, socket: socket}
  end

  test "command without params that returns action without params", %{socket: socket} do
    target_module = %{
      "type" => "module",
      "className" => @class_name_1
    }

    message = %{
      target_module: target_module,
      target_id: @target_id,
      command: %{"type" => "atom", "value" => "test_command"},
      params: %{"type" => "list", data: []}
    }

    ref = push(socket, "command", message)

    expected_response =
      {"test_target_id", :test_action, %{}}
      |> Serializer.serialize()

    assert_reply ref, :ok, ^expected_response
  end

  test "command without params that returns action with params", %{socket: socket} do
    target_module = %{
      "type" => "module",
      "className" => @class_name_3
    }

    message = %{
      target_module: target_module,
      target_id: @target_id,
      command: %{"type" => "atom", "value" => "test_command"},
      params: %{"type" => "list", data: []}
    }

    ref = push(socket, "command", message)

    expected_response =
      {"test_target_id", :test_action, %{a: 1, b: 2}}
      |> Serializer.serialize()

    assert_reply ref, :ok, ^expected_response
  end

  test "command with params that returns action without params", %{socket: socket} do
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
      {"test_target_id", :test_action_1, %{}}
      |> Serializer.serialize()

    assert_reply ref, :ok, ^expected_response
  end

  test "command with params that returns action with params", %{socket: socket} do
    target_module = %{
      "type" => "module",
      "className" => @class_name_2
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
      {"test_target_id", :test_action, %{a: 10, b: 20}}
      |> Serializer.serialize()

    assert_reply ref, :ok, ^expected_response
  end

  test "__redirect__ command", %{socket: socket} do
    compile_pages("test/fixtures/runtime/channel")

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
      {"test_target_id", :__redirect__, %{html: html, url: "/test-route"}}
      |> Serializer.serialize()

    ref = push(socket, "command", message)
    assert_reply ref, :ok, ^expected_response
  end
end
