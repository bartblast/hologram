defmodule Hologram.Test.Fixtures.Template.Renderer.Module148 do
  use Hologram.Component

  state :copy, :any
  state :step, :integer, default: 1

  derived :double, :integer, fn step -> step * 2 end

  @impl Component
  def init(_props, component, _server) do
    put_state(component, :copy, component.derived.double)
  end

  @impl Component
  def template do
    ~HOLO"{@double}"
  end
end
