defmodule Hologram.Test.Fixtures.Template.Renderer.Module16 do
  use Hologram.Component

  prop :prop_1
  prop :prop_2
  prop :prop_3

  @impl Component
  def init(props, client, _server) do
    put_state(client, props)
  end

  @impl Component
  def template do
    ~H""
  end
end
