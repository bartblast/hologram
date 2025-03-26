# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module12 do
  use Hologram.Component

  def init(_props, component, _server) do
    put_state(component, a: 12)
  end

  @impl Component
  def template do
    ~HOLO"""
    {@a},<slot />
    """
  end
end
