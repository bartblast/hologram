# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module121 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module122

  route "/hologram-test-fixtures-template-renderer-module121"

  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  @impl Page
  def template do
    ~HOLO"""
    <Module122 />
    """
  end
end
