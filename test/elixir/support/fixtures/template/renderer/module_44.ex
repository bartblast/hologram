defmodule Hologram.Test.Fixtures.Template.Renderer.Module44 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Template.Renderer.Module38

  @impl Component
  def init(_props, component, _server) do
    put_context(component, {:my_scope, :my_key}, 123)
  end

  @impl Component
  def template do
    ~HOLO"""
    <Module38 />
    """
  end
end
