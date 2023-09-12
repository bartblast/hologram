defmodule Hologram.Test.Fixtures.Template.Renderer.Module37 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Template.Renderer.Module38

  @impl Component
  def init(_props, client, _server) do
    put_context(client, {:my_scope, :my_key}, 123)
  end

  @impl Component
  def template do
    ~H"""
    <Module38 />
    """
  end
end
