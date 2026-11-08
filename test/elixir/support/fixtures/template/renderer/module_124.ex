defmodule Hologram.Test.Fixtures.Template.Renderer.Module124 do
  use Hologram.Component

  state :password, :string, default: "hunter2", secret: true

  @impl Component
  def init(_props, component, _server) do
    :erlang.error(component.state)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
