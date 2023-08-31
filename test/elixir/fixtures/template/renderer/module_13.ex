defmodule Hologram.Test.Fixtures.Template.Renderer.Module13 do
  use Hologram.Component

  prop :my_prop

  @impl Component
  def init(_props, client, _server) do
    put_state(client, a: 1)
  end

  @impl Component
  def template do
    ~H"""
    {@a}
    """
  end
end
