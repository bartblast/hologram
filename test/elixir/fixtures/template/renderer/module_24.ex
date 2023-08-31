defmodule Hologram.Test.Fixtures.Template.Renderer.Module24 do
  use Hologram.Page

  route "/module_24"

  layout Hologram.Test.Fixtures.Template.Renderer.Module23,
    key_1: "prop_value_1",
    key_2: "prop_value_2"

  @impl Page
  def template do
    ~H""
  end
end
