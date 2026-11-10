defmodule Hologram.Test.Fixtures.Template.Renderer.Module116 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module89

  route "/hologram-test-fixtures-template-renderer-module116"

  layout Hologram.Test.Fixtures.Template.Renderer.Module114

  # The spread keeps the build from refusing the missing prop, so the render raises for it instead.
  @impl Page
  def template do
    ~HOLO"""
    <Module89 ...{%{}} />
    """
  end
end
