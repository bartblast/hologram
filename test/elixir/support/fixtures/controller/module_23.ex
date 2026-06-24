# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module23 do
  use Hologram.Component

  @impl Component
  def middleware(server) do
    put_status(server, :forbidden)
  end

  @impl Component
  def command(:my_command, _params, _server) do
    raise "command must not run when middleware produces a terminal response"
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
