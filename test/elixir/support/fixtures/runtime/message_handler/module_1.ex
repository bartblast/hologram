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

  def command(:my_command_with_cookies, _params, server) do
    put_cookie(server, "test_cookie", "test_value")
  end

  def command(:my_command_without_cookies, _params, server) do
    %{server | next_action: nil}
  end

  def command(:my_command_accessing_cookie, _params, server) do
    put_action(server, get_cookie(server, "my_cookie"))
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
