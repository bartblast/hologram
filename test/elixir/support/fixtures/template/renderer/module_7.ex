# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module7 do
  use Hologram.Component

  def init(_props, component, _server) do
    put_state(component, c: 3, d: 4)
  end

  @impl Component
  def template do
    ~HOLO"""
    <div>state_c = {@c}, state_d = {@d}</div>
    """
  end
end
