defmodule Hologram.Test.Fixtures.Template.Renderer.Module115 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module115"

  state :password, :string, default: "", secret: true

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO""
  end
end
