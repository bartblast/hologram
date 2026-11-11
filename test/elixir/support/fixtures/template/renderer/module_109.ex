defmodule Hologram.Test.Fixtures.Template.Renderer.Module109 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module109/:id"

  param :id, :integer

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(params, component, _server) do
    put_state(component, params)
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
