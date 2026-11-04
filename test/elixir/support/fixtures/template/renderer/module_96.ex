# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module96 do
  use Hologram.Component

  prop :items, :list

  @impl Component
  def template do
    ~HOLO"""
    <ul>{%for item <- @items}<li>{item.name}</li>{/for}</ul>
    """
  end
end
