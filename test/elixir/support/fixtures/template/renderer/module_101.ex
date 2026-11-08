# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module101 do
  use Hologram.Component

  state :a, :integer, default: 1
  state :b, :string, default: "abc"
  state :c, :map

  @impl Component
  def init(_props, component, _server) do
    put_state(component, b: "xyz", c: component.state)
  end

  @impl Component
  def template do
    ~HOLO"<div>state_a = {@a}, state_b = {@b}</div>"
  end
end
