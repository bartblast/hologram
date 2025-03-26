defmodule Hologram.Test.Fixtures.Template.Renderer.Module62 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module62"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html>
      <body>
        Module62
      </body>
    </html>
    """
  end
end
