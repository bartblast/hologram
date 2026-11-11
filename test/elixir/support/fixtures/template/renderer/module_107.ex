defmodule Hologram.Test.Fixtures.Template.Renderer.Module107 do
  use Hologram.Component

  state :values, :map, default: %{}

  @impl Component
  def init(_props, component, _server) do
    put_state(component, [:values, :x], 1)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
