defmodule Hologram.Test.Fixtures.Template.Renderer.Module30 do
  use Hologram.Component

  state :state_1, :string
  state :state_2, :string

  @impl Component
  def init(_props, component, _server) do
    put_state(component, state_1: "value_1", state_2: "value_2")
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
