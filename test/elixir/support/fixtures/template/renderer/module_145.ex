defmodule Hologram.Test.Fixtures.Template.Renderer.Module145 do
  use Hologram.Component

  state :step, :integer, default: 1

  # Counts its own computations, so a test can tell how many times the render computed it.
  derived :double, :integer, fn step ->
    Process.put(:module_145_computations, Process.get(:module_145_computations, 0) + 1)

    step * 2
  end

  @impl Component
  def init(_props, component, _server) do
    put_state(component, :step, 5)
  end

  @impl Component
  def template do
    ~HOLO"double = {@double}"
  end
end
