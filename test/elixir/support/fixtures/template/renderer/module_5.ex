# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module5 do
  use Hologram.Component

  prop :a, :string
  prop :b, :string

  def init(_props, _component, server) do
    put_cookie(server, "cookie_key_5", :cookie_value_5)
  end

  @impl Component
  def template do
    ~HOLO"""
    <div>prop_a = {@a}, prop_b = {@b}</div>
    """
  end
end
