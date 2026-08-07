defmodule HologramFeatureTests.Components.TemplateSyntax.Component2 do
  use Hologram.Component

  prop :dom_id, :string
  prop :prop_1, :string

  def template do
    ~HOLO"""
    <div id={@dom_id}>prop_1 = {@prop_1}</div>
    """
  end
end
