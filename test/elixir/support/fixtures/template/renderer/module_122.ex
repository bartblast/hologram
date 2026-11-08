defmodule Hologram.Test.Fixtures.Template.Renderer.Module122 do
  use Hologram.Component

  @impl Component
  def init(_props, component, _server) do
    %{step: _step} = component.state
    component
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
