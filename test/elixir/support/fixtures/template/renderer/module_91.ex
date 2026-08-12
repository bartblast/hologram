# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module91 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module92

  route "/hologram-test-fixtures-template-renderer-module91"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module92 />
    """
  end
end
