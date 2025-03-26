# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module3 do
  use Hologram.Component

  def init(_props, component, _server) do
    put_state(component, a: 1, b: 2)
  end

  @impl Component
  def template do
    ~HOLO"""
    <div>state_a = {@a}, state_b = {@b}</div>
    """
  end
end
