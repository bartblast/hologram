defmodule Hologram.Test.Fixtures.Template.Renderer.Module39 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Template.Renderer.Module38

  route "/hologram-test-fixtures-template-renderer-module39"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, _server) do
    put_context(component, {:my_scope, :my_key}, 123)
  end

  @impl Page
  def template do
    ~HOLO"""
    <Module38 />
    """
  end
end
