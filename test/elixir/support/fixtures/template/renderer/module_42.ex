defmodule Hologram.Test.Fixtures.Template.Renderer.Module42 do
  use Hologram.Component

  @impl Component
  def init(_props, component, _server) do
    put_context(component, {:my_scope, :my_key}, 123)
  end

  @impl Component
  def template do
    ~HOLO"<slot />"
  end
end
