# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module165 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module157

  route "/hologram-test-fixtures-template-renderer-module165"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module157 />
    """
  end
end
