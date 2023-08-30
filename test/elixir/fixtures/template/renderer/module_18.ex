defmodule Hologram.Test.Fixtures.Template.Renderer.Module18 do
  use Hologram.Component

  prop :a

  @impl Component
  def init(_props, client, _server) do
    put_state(client, :b, 222)
  end

  @impl Component
  def template do
    ~H"""
    var_a = {@a}, var_b = {@b}, var_c = {@c}
    """
  end
end
