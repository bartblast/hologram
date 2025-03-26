# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Socket.Channel.Module1 do
  use Hologram.Component

  def template do
    ~HOLO""
  end

  def command(:my_command_a, _params, server) do
    server
  end

  def command(:my_command_b, %{a: a, b: b}, server) do
    put_action(server, :my_action_b, c: a + b)
  end

  def command(:my_command_c, %{a: a, b: b}, server) do
    put_action(server, name: :my_action_c, params: [c: a + b], target: "my_target_2")
  end
end
