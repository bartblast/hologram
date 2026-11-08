defmodule Hologram.Test.Fixtures.Template.Renderer.Module120 do
  use Hologram.Component

  state :password, :string, default: "hunter2", secret: true

  @impl Component
  def init(_props, component, _server) do
    %{step: step} = component.state
    put_state(component, :password, step)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
