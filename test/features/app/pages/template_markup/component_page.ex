defmodule HologramFeatureTests.TemplateMarkup.ComponentPage do
  use Hologram.Page
  alias HologramFeatureTests.Components.TemplateMarkup.Component1

  route "/template-markup/component"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~H"""
    <Component1 my_prop="abc" />
    """
  end
end
