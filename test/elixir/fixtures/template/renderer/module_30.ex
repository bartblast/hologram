defmodule Hologram.Test.Fixtures.Template.Renderer.Module30 do
  use Hologram.Layout

  @impl Layout
  def init(_props, component, _server) do
    put_state(component, state_1: "value_1", state_2: "value_2")
  end

  @impl Layout
  def template do
    ~H""
  end
end
