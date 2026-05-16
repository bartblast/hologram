# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module79 do
  use Hologram.Component

  def init(_props, component, server) do
    {put_state(component, observed_cid: server.cid), server}
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
