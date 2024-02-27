# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module2 do
  use Hologram.Component

  prop :a, :string
  prop :b, :integer
  prop :c, :string

  def init(_props, component) do
    component
  end

  @impl Component
  def template do
    ~H"""
    <div>prop_a = {@a}, prop_b = {@b}, prop_c = {@c}</div>
    """
  end
end
