# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module5 do
  use Hologram.Component

  prop :a, :string
  prop :b, :string

  def init(_props, _component, server) do
    server
  end

  @impl Component
  def template do
    ~HOLO"""
    <div>prop_a = {@a}, prop_b = {@b}</div>
    """
  end
end
