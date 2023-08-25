defmodule Hologram.Test.Fixtures.Template.Renderer.Module7 do
  use Hologram.Component

  @impl Component
  def init(_props, client, _server) do
    put_state(client, c: 3, d: 4)
  end

  @impl Component
  def template do
    ~H"""
    <div>state_c = {@c}, state_d = {@d}</div>
    """
  end
end
