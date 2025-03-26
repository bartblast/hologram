# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module10 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Template.Renderer.Module11
  alias Hologram.Test.Fixtures.Template.Renderer.Module12

  def init(_props, component, _server) do
    put_state(component, a: 10)
  end

  @impl Component
  def template do
    ~HOLO"""
    {@a},<Module11 cid="component_11">{@a},<Module12 cid="component_12">{@a}</Module12></Module11>
    """
  end
end
