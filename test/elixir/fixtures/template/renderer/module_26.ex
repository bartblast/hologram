defmodule Hologram.Test.Fixtures.Template.Renderer.Module26 do
  use Hologram.Layout

  prop :prop_1
  prop :prop_3

  @impl Layout
  def init(props, client, _server) do
    put_state(client, props)
  end

  @impl Layout
  def template do
    ~H""
  end
end
