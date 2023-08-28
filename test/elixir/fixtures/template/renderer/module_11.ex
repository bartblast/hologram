defmodule Hologram.Test.Fixtures.Template.Renderer.Module11 do
  use Hologram.Component

  @impl Component
  def init(_props, client, _server) do
    put_state(client, a: 11)
  end

  @impl Component
  def template do
    ~H"""
    {@a},<slot />
    """
  end
end
