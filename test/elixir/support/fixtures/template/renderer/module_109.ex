# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module109 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module94

  route "/hologram-test-fixtures-template-renderer-module109"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module94 />
    """
  end
end
