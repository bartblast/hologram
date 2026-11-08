defmodule Hologram.Test.Fixtures.Template.Renderer.Module127 do
  use Hologram.Component

  state :password, :string, default: "hunter2", secret: true

  @impl Component
  def init(_props, component, _server) do
    put_state(component, :password, component.state.pasword)
  rescue
    error -> reraise error, __STACKTRACE__
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
