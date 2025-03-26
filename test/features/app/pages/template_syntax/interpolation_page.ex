defmodule HologramFeatureTests.TemplateSyntax.InterpolationPage do
  use Hologram.Page

  route "/template-syntax/interpolation"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <span class="node_1">a{1 + 1}c</div>

    <span class="node_{1 + 1}">xyz</span>
    """
  end
end
