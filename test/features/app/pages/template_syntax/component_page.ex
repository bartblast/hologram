defmodule HologramFeatureTests.TemplateSyntax.ComponentPage do
  use Hologram.Page
  alias HologramFeatureTests.Components.TemplateSyntax.Component1

  route "/template-syntax/component"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component1 my_prop="abc" />
    """
  end
end
