defmodule Hologram.Test.Fixtures.Template.Renderer.Module43 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Template.Renderer.Module38

  route "/hologram-test-fixtures-template-renderer-module43"

  layout Hologram.Test.Fixtures.Template.Renderer.Module42

  @impl Page
  def template do
    ~HOLO"""
    <Module38 />
    """
  end
end
