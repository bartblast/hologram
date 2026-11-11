# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module129 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module130

  route "/hologram-test-fixtures-template-renderer-module129"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module130 />
    """
  end
end
