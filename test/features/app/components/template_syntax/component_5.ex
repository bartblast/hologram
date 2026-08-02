defmodule HologramFeatureTests.Components.TemplateSyntax.Component5 do
  use Hologram.Component

  prop :dom_id, :string

  def template do
    ~HOLO"""
    <div id={@dom_id}>slot content = <slot /></div>
    """
  end
end
