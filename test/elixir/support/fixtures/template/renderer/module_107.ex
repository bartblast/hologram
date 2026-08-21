# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module107 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module108

  route "/hologram-test-fixtures-template-renderer-module107"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    <Module108 />
    """
  end
end
