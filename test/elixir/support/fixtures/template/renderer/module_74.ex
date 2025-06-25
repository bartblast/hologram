defmodule Hologram.Test.Fixtures.Template.Renderer.Module74 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Template.Renderer.Module75

  @impl Component
  def init(_props, _component, server) do
    put_cookie(server, "cookie_key_74", :cookie_value_74)
  end

  @impl Component
  def template do
    ~HOLO"""
    <Module75 cid="component_75" />
    """
  end
end
