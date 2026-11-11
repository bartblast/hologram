# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module135 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module134

  route "/hologram-test-fixtures-template-renderer-module135"

  # The layout that renders Hologram.UI.Runtime, which is what puts the mount data - the carried
  # rows among it - into the page.
  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  @impl Page
  def template do
    ~HOLO"""
    <Module134 />
    """
  end
end
