defmodule Hologram.Test.Fixtures.Template.Renderer.Module72 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Template.Renderer.Module73

  def init(_props, _component, server) do
    put_cookie(server, "cookie_key_72", :cookie_value_72)
  end

  @impl Component
  def template do
    ~HOLO"""
    <Module73 cid="component_73" />
    """
  end
end
