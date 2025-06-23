# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Runtime.MessageHandler.Module1 do
  use Hologram.Component
  alias Hologram.Component.Action

  def command(:my_command_a, _params, server) do
    %{server | next_action: nil}
  end

  def command(:my_command_b, %{a: a, b: b}, server) do
    action = %Action{
      name: :my_action_b,
      params: %{c: a + b},
      target: nil
    }

    %{server | next_action: action}
  end

  def command(:my_command_c, %{a: a, b: b}, server) do
    action = %Action{
      name: :my_action_c,
      params: %{c: a + b},
      target: "my_target_2"
    }

    %{server | next_action: action}
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
