# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module6 do
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
    put_cookie(server, "my_cookie_name", "my_cookie_value")
  end

  def command(:my_command_with_session, _params, server) do
    put_session(server, "my_session_key", "my_session_value")
  end

  def command(:my_command_without_cookies, _params, server) do
    %{server | next_action: nil}
  end

  def command(:my_command_without_session, _params, server) do
    %{server | next_action: nil}
  end

  def command(:my_command_accessing_cookie, _params, server) do
    put_action(server, get_cookie(server, "my_cookie_name"))
  end

  def command(:my_command_accessing_session, _params, server) do
    put_action(server, get_session(server, "my_session_key"))
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
