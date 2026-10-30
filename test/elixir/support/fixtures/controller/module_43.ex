# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module43 do
  use Hologram.Component

  middleware :deny

  def deny(server, _opts) do
    server
    |> put_response_header("content-type", "text/plain")
    |> put_response_body("denied")
    |> put_status(:forbidden)
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
