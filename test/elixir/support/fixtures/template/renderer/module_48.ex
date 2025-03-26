defmodule Hologram.Test.Fixtures.Template.Renderer.Module48 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module48"

  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  @impl Page
  def template do
    ~HOLO"""
    page template
    """
  end
end
