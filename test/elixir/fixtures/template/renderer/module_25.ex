defmodule Hologram.Test.Fixtures.Template.Renderer.Module25 do
  use Hologram.Page

  route "/module_25"

  layout Hologram.Test.Fixtures.Template.Renderer.Module26,
    prop_1: "prop_value_1",
    prop_2: "prop_value_2",
    prop_3: "prop_value_3"

  @impl Page
  def template do
    ~H""
  end
end
