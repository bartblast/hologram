# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module120 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module119

  route "/hologram-test-fixtures-template-renderer-module120"

  # The layout that renders Hologram.UI.Runtime, which is what puts the mount data - the seed
  # among it - into the page.
  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  @impl Page
  def template do
    ~HOLO"""
    <Module119 />
    """
  end
end
