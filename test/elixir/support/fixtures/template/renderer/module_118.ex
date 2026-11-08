defmodule Hologram.Test.Fixtures.Template.Renderer.Module118 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module118"

  state :password, :string, default: "hunter2", secret: true

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"{@missing}"
  end
end
