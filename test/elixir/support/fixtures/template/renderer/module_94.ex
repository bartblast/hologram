defmodule Hologram.Test.Fixtures.Template.Renderer.Module94 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module94"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, _server) do
    put_state(component, :b, 222)
  end

  @impl Page
  def template do
    ~HOLO"""
    var_b = {@b}, var_c = {@c}
    """
  end
end
