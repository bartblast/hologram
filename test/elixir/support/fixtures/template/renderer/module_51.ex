# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module51 do
  use Hologram.Component

  def init(_props, component, server) do
    {
      put_state(component, a: 1, b: 2),
      put_cookie(server, "cookie_key_51", :cookie_value_51)
    }
  end

  @impl Component
  def template do
    ~HOLO"""
    <div>state_a = {@a}</div><div>state_b = {@b}</div>
    """
  end
end
