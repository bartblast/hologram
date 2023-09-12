defmodule Hologram.Test.Fixtures.Template.Renderer.Module44 do
  use Hologram.Layout
  alias Hologram.Test.Fixtures.Template.Renderer.Module38

  @impl Layout
  def init(_params, client, _server) do
    put_context(client, {:my_scope, :my_key}, 123)
  end

  @impl Layout
  def template do
    ~H"""
    <Module38 />
    """
  end
end
