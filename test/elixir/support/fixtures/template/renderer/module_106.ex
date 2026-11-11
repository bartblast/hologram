defmodule Hologram.Test.Fixtures.Template.Renderer.Module106 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module106"

  state :a, :integer

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, _server) do
    put_state(component, a: 1, b: 2)
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
