defmodule Hologram.Test.Fixtures.Template.Renderer.Module119 do
  use Hologram.Component

  state :password, :string, default: "hunter2", secret: true

  @impl Component
  def init(_props, component, _server) do
    put_state(component, :password, Map.fetch!(component.props, :x))
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
