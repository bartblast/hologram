defmodule Hologram.Test.Fixtures.Template.Renderer.Module123 do
  use Hologram.Component

  state :password, :string, default: "hunter2", secret: true

  @impl Component
  def init(_props, component, _server) do
    %{step: _step} = component.props
    component
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
