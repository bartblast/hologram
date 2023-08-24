defmodule Hologram.Test.Fixtures.Template.Renderer.Module6 do
  use Hologram.Component

  @impl Component
  def init(_props, client, server) do
    new_client = put_state(client, a: 1, b: 2)
    {new_client, server}
  end

  @impl Component
  def template do
    ~H"""
    <div>state_a = {@a}, state_b = {@b}</div>
    """
  end
end
