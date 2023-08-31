defmodule Hologram.Test.Fixtures.Template.Renderer.Module23 do
  use Hologram.Layout

  prop :key_1
  prop :key_2

  @impl Layout
  def init(_params, client, _server) do
    put_state(client, key_2: "state_value_2", key_3: "state_value_3")
  end

  @impl Layout
  def template do
    ~H"""
    key_1 = {@key_1}, key_2 = {@key_2}, key_3 = {@key_3}
    """
  end
end
