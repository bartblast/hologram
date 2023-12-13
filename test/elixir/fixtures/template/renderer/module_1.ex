defmodule Hologram.Test.Fixtures.Template.Renderer.Module1 do
  use Hologram.Component

  def init(_props, client) do
    client
  end

  @impl Component
  def template do
    ~H"""
    <div>abc</div>
    """
  end
end
