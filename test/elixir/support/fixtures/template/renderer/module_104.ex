defmodule Hologram.Test.Fixtures.Template.Renderer.Module104 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module104"

  state :a, :integer, default: 1
  state :b, :string, default: "abc"
  state :c, :map

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, _server) do
    put_state(component, b: "xyz", c: component.state)
  end

  @impl Page
  def template do
    ~HOLO"page state_a = {@a}, state_b = {@b}"
  end
end
