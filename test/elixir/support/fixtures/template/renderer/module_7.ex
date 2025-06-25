# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module7 do
  use Hologram.Component

  def init(_props, component, server) do
    {
      put_state(component, c: 3, d: 4),
      put_cookie(server, "cookie_key_7", :cookie_value_7)
    }
  end

  @impl Component
  def template do
    ~HOLO"""
    <div>state_c = {@c}, state_d = {@d}</div>
    """
  end
end
