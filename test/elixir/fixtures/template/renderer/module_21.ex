defmodule Hologram.Test.Fixtures.Template.Renderer.Module21 do
  use Hologram.Page

  route "/module_21"

  param :key_1
  param :key_2

  layout Hologram.Test.Fixtures.Template.Renderer.Module22

  @impl Page
  def init(_params, client, _server) do
    put_state(client, key_2: "state_value_2", key_3: "state_value_3")
  end

  @impl Page
  def template do
    ~H"""
    key_1 = {@key_1}, key_2 = {@key_2}, key_3 = {@key_3}
    """
  end
end
