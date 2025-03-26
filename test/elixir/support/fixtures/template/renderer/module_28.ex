defmodule Hologram.Test.Fixtures.Template.Renderer.Module28 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module28"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, _server) do
    put_state(component, state_1: "value_1", state_2: "value_2")
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
