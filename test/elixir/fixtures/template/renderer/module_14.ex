defmodule Hologram.Test.Fixtures.Template.Renderer.Module14 do
  use Hologram.Page

  route "/module_14"

  layout Hologram.Test.Fixtures.Template.Renderer.Module15

  @impl Page
  def template do
    ~H"""
    page template
    """
  end
end
