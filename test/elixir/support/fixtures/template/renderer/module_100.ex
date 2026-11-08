# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module100 do
  use Hologram.Component

  state :a, :integer, default: 1
  state :b, :string, default: "abc"
  state :c, :map

  @impl Component
  def template do
    ~HOLO"<div>state_a = {@a}, state_b = {@b}</div>"
  end
end
