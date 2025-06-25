defmodule Hologram.Test.Fixtures.Template.Renderer.Module69 do
  use Hologram.Component

  @impl Component
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
