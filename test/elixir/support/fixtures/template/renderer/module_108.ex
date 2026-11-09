defmodule Hologram.Test.Fixtures.Template.Renderer.Module108 do
  use Hologram.Component

  prop :label, :string

  @impl Component
  def init(props, component, _server) do
    put_state(component, props)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
