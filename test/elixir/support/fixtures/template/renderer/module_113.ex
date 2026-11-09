defmodule Hologram.Test.Fixtures.Template.Renderer.Module113 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module113"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, _server) do
    put_state(component, :cid, "my_cid")
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
