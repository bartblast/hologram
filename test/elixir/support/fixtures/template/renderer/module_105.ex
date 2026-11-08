defmodule Hologram.Test.Fixtures.Template.Renderer.Module105 do
  use Hologram.Component

  state :a, :integer

  @impl Component
  def init(_props, component, _server) do
    put_state(component, a: 1, b: 2, c: 3)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
