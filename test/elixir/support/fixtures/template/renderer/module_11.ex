# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module11 do
  use Hologram.Component

  def init(_props, component, _server) do
    put_state(component, a: 11)
  end

  @impl Component
  def template do
    ~H"""
    {@a},<slot />
    """
  end
end
