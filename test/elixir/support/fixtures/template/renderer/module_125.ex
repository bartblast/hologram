# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module125 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module124

  route "/hologram-test-fixtures-template-renderer-module125"

  # The layout that renders Hologram.UI.Runtime, which is what puts the mount data - the counts
  # among it - into the page.
  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  @impl Page
  def template do
    ~HOLO"""
    <Module124 a={true} />
    <Module124 a={false} />
    """
  end
end
