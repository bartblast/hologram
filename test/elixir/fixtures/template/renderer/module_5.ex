defmodule Hologram.Test.Fixtures.Template.Renderer.Module5 do
  use Hologram.Component

  @impl Component
  def init(_props, _client, server) do
    server
  end

  @impl Component
  def template do
    ~H"""
    <div>prop_a = {@a}, prop_b = {@b}</div>
    """
  end
end
