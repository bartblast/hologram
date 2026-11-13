defmodule Hologram.Test.Fixtures.Template.Renderer.Module122 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module122"

  layout Hologram.Test.Fixtures.LayoutFixture

  state :b, :integer

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
