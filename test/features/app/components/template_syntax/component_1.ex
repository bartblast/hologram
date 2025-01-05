defmodule HologramFeatureTests.Components.TemplateSyntax.Component1 do
  use Hologram.Component

  prop :my_prop, :string

  def template do
    ~H"""
    <div id="my_component">{@my_prop}</div>
    """
  end
end
