# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Socket.Channel.Module6 do
  use Hologram.Component

  def template do
    ~HOLO""
  end

  def command(:my_command_6, _params, server) do
    put_action(server, :my_action_6, fun: fn x -> x end)
  end
end
