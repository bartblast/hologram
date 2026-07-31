defmodule HologramFeatureTests.Components.TemplateSyntax.Component4 do
  use Hologram.Component

  prop :html_attrs, :map

  def template do
    ~HOLO"""
    <span ...{@html_attrs}>forwarded</span>
    """
  end
end
