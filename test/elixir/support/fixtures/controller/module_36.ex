# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module36 do
  use Hologram.Component

  middleware :mark

  def mark(server, _opts) do
    put_response_header(server, "x-my-header", "my_value")
  end

  @impl Component
  def command(:my_command, _params, server) do
    server
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
