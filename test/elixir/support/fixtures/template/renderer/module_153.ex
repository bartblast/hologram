defmodule Hologram.Test.Fixtures.Template.Renderer.Module153 do
  use Hologram.Component

  state :pending, :string
  state :step, :integer, default: 1

  derived :double, :integer, fn step -> step * 2 end

  @impl Component
  def init(_props, component, _server) do
    put_state(component, :pending, inspect(component.derived.double))
  end

  @impl Component
  def template do
    ~HOLO"pending = {@pending}"
  end
end
