# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module167 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module166

  route "/hologram-test-fixtures-template-renderer-module167"

  # The layout that renders Hologram.UI.Runtime, which is what puts the mount data - the rows a
  # page carries among it - into the page.
  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  @impl Page
  def template do
    ~HOLO"""
    <Module166 />
    """
  end
end
