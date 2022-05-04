defmodule Hologram.Runtime.ChannelTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.Serializer
  alias Hologram.Conn
  alias Hologram.Runtime
  alias Hologram.Runtime.Channel
  alias Hologram.Template.Renderer

  @class_name_1 "Elixir_Hologram_Test_Fixtures_Runtime_Channel_Module1"
  @class_name_3 "Elixir_Hologram_Test_Fixtures_Runtime_Channel_Module3"
  @class_name_4 "Elixir_Hologram_Test_Fixtures_Runtime_Channel_Module4"
  @class_name_5 "Elixir_Hologram_Test_Fixtures_Runtime_Channel_Module5"
  @class_name_6 "Elixir_Hologram_Test_Fixtures_Runtime_Channel_Module6"
  @class_name_7 "Elixir_Hologram_Test_Fixtures_Runtime_Channel_Module7"

  @module_5 Hologram.Test.Fixtures.Runtime.Channel.Module5
  @target_id %{"type" => "atom", "value" => "test_target_id_value"}

  defp build_message(target_module, target_id) do
    %{
      "target_module" => target_module,
      "target_id" => target_id,
      "command" => %{"type" => "atom", "value" => "test_command"},
      "params" => %{"type" => "list", "data" => []}
    }
  end

  test "command returning target_id, action and params" do
    target_module = %{
      "type" => "module",
      "className" => @class_name_6
    }

    message = build_message(target_module, @target_id)
    reply = Channel.handle_in("command", message, :socket_dummy)

    expected_response =
      {:test_action_target_id, :test_action, %{a: 1, b: 2}}
      |> Serializer.serialize()

    expected_reply = {:reply, {:ok, expected_response}, :socket_dummy}

    assert reply == expected_reply
  end

  test "command returning target_id and action" do
    target_module = %{
      "type" => "module",
      "className" => @class_name_7
    }

    message = build_message(target_module, @target_id)
    reply = Channel.handle_in("command", message, :socket_dummy)

    expected_response =
      {:test_action_target_id, :test_action, %{}}
      |> Serializer.serialize()

    expected_reply = {:reply, {:ok, expected_response}, :socket_dummy}

    assert reply == expected_reply
  end

  test "command returning action and params" do
    target_module = %{
      "type" => "module",
      "className" => @class_name_3
    }

    message = build_message(target_module, @target_id)
    reply = Channel.handle_in("command", message, :socket_dummy)

    expected_response =
      {:test_target_id_value, :test_action, %{a: 1, b: 2}}
      |> Serializer.serialize()

    expected_reply = {:reply, {:ok, expected_response}, :socket_dummy}

    assert reply == expected_reply
  end

  test "command returning action only" do
    target_module = %{
      "type" => "module",
      "className" => @class_name_1
    }

    message = build_message(target_module, @target_id)
    reply = Channel.handle_in("command", message, :socket_dummy)

    expected_response =
      {:test_target_id_value, :test_action, %{}}
      |> Serializer.serialize()

    expected_reply = {:reply, {:ok, expected_response}, :socket_dummy}

    assert reply == expected_reply
  end

  test "command which receives params" do
    target_module = %{
      "type" => "module",
      "className" => @class_name_4
    }

    message = %{
      "target_module" => target_module,
      "target_id" => @target_id,
      "command" => %{"type" => "atom", "value" => "test_command"},
      "params" => %{
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

    reply = Channel.handle_in("command", message, :socket_dummy)

    expected_response =
      {:test_target_id_value, :test_action_1, %{}}
      |> Serializer.serialize()

    expected_reply = {:reply, {:ok, expected_response}, :socket_dummy}

    assert reply == expected_reply
  end

  test "command returning __redirect__ action" do
    [
      app_path: "#{@fixtures_path}/runtime/channel",
      templatables: [Hologram.Test.Fixtures.App.DefaultLayout]
    ]
    |> compile()

    Runtime.run()

    target_module = %{
      "type" => "module",
      "className" => @class_name_5
    }

    message = %{
      "target_module" => target_module,
      "target_id" => @target_id,
      "command" => %{"type" => "atom", "value" => "__redirect__"},
      "params" => %{
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

    reply = Channel.handle_in("command", message, :socket_dummy)

    html = Renderer.render(@module_5, %Conn{}, %{})

    expected_response =
      {:test_target_id_value, :__redirect__, %{html: html, url: "/test-route-5"}}
      |> Serializer.serialize()

    expected_reply = {:reply, {:ok, expected_response}, :socket_dummy}

    assert reply == expected_reply
  end
end
