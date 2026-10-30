# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module113 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module112

  route "/hologram-test-fixtures-template-renderer-module113"

  # The layout that renders Hologram.UI.Runtime, which is what puts the mount data - the carried
  # rows among it - into the page.
  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  @impl Page
  def template do
    ~HOLO"""
    <Module112 />
    """
  end
end
