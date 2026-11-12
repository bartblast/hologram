defmodule Hologram.Test.Fixtures.Template.Renderer.Module155 do
  use Hologram.Component

  state :step, :integer, default: 3

  derived :double, :integer, fn step -> step * 2 end

  @impl Component
  def init(_props, _component, server) do
    server
  end

  @impl Component
  def template do
    ~HOLO"double = {@double}"
  end
end
