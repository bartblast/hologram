# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module4 do
  use Hologram.Component

  prop :b, :string
  prop :c, :string

  def init(_props, component, _server) do
    put_state(component, a: "state_a", b: "state_b")
  end

  @impl Component
  def template do
    ~HOLO"""
    <div>var_a = {@a}, var_b = {@b}, var_c = {@c}</div>
    """
  end
end
