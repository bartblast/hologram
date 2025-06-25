defmodule Hologram.Test.Fixtures.Template.Renderer.Module71 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Template.Renderer.Module74

  def init(_props, _component, server) do
    put_cookie(server, "cookie_key_layout", :cookie_value_layout)
  end

  @impl Component
  def template do
    ~HOLO"""
    <slot />
    <Module74 cid="component_74" />
    """
  end
end
