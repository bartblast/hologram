defmodule Hologram.Test.Fixtures.Template.Renderer.Module14 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module14"

  layout Hologram.Test.Fixtures.Template.Renderer.Module15

  @impl Page
  def template do
    ~HOLO"""
    page template
    """
  end
end
