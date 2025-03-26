defmodule HologramFeatureTests.TemplateSyntax.TextAndElementPage do
  use Hologram.Page

  route "/template-syntax/text-and-element"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <div class="parent_elem">
      <span class="child_elem">my text</span>
    </div>
    """
  end
end
