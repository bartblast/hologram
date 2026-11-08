defmodule Hologram.Test.Fixtures.Template.Renderer.Module110 do
  use Hologram.Component

  @impl Component
  def init(_props, component, _server) do
    put_state(component, %{"b" => 2})
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
