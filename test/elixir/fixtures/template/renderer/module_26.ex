defmodule Hologram.Test.Fixtures.Template.Renderer.Module26 do
  use Hologram.Layout

  prop :prop_1, :string
  prop :prop_3, :string

  @impl Layout
  def init(props, client, _server) do
    put_state(client, props)
  end

  @impl Layout
  def template do
    ~H""
  end
end
