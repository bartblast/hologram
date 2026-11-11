# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module131 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module138

  route "/hologram-test-fixtures-template-renderer-module131"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module138 />
    """
  end
end
