defmodule HologramFeatureTests.Pages.TemplateFunctionPage do
  use Hologram.Page

  route "/pages/template-function"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"Template defined in function"
  end
end
