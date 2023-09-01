defmodule Hologram.Test.Fixtures.Template.Renderer.Module28 do
  use Hologram.Page

  route "/module_28"

  layout Hologram.Test.Fixtures.Template.Renderer.Module22

  @impl Page
  def init(_params, client, _server) do
    put_state(client, state_1: "value_1", state_2: "value_2")
  end

  @impl Page
  def template do
    ~H""
  end
end
