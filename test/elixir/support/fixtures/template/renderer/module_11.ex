# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module11 do
  use Hologram.Component

  def init(_props, component, server) do
    {
      put_state(component, a: 11),
      put_cookie(server, "cookie_key_11", :cookie_value_11)
    }
  end

  @impl Component
  def template do
    ~HOLO"""
    {@a},<slot />
    """
  end
end
