defmodule Hologram.Test.Fixtures.Template.Renderer.Module4 do
  use Hologram.Component

  @impl Component
  def init(_props, client, _server) do
    put_state(client, a: "state_a", b: "state_b")
  end

  @impl Component
  def template do
    ~H"""
    <div>var_a = {@a}, var_b = {@b}, var_c = {@c}</div>
    """
  end
end
