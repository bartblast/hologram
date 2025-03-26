defmodule HologramFeatureTests.Components.TemplateSyntax.Component1 do
  use Hologram.Component

  prop :my_prop, :string

  def template do
    ~HOLO"""
    <div id="my_component">{@my_prop}</div>
    """
  end
end
