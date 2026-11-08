defmodule Hologram.Test.Fixtures.Template.Renderer.Module125 do
  use Hologram.Component

  state :password, :string, default: "hunter2", secret: true

  @impl Component
  def init(_props, component, _server) do
    put_state(component, :password, to_string(component.state))
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
