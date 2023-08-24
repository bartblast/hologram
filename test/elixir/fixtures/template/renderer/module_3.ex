defmodule Hologram.Test.Fixtures.Template.Renderer.Module3 do
  use Hologram.Component

  def init(_props, client, _server) do
    put_state(client, a: 1, b: 2)
  end

  @impl Component
  def template do
    ~H"""
    <div>state_a = {@a}, state_b = {@b}</div>
    """
  end
end
