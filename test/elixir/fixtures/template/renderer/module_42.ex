defmodule Hologram.Test.Fixtures.Template.Renderer.Module42 do
  use Hologram.Layout

  @impl Layout
  def init(_params, client, _server) do
    put_context(client, {:my_scope, :my_key}, 123)
  end

  @impl Layout
  def template do
    ~H"<slot />"
  end
end
