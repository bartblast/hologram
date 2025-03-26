# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module18 do
  use Hologram.Component

  prop :a, :string

  def init(_props, component, _server) do
    put_state(component, :b, 222)
  end

  @impl Component
  def template do
    ~HOLO"""
    var_a = {@a}, var_b = {@b}, var_c = {@c}
    """
  end
end
