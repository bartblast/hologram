# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module6 do
  use Hologram.Component

  def init(_props, component, server) do
    new_component = put_state(component, a: 1, b: 2)
    {new_component, server}
  end

  @impl Component
  def template do
    ~HOLO"""
    <div>state_a = {@a}, state_b = {@b}</div>
    """
  end
end
