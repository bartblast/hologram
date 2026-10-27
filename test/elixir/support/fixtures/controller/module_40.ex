# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module40 do
  use Hologram.Component

  @impl Component
  def init(_props, _component, server) do
    put_response_header(server, "x-layout-header", "my_value")
  end

  @impl Component
  def template do
    ~HOLO"<slot />"
  end
end
