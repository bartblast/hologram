# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module96 do
  use Hologram.Component

  def init(_props, component, _server) do
    put_state(component, %{:b => 222, "c" => 333})
  end

  @impl Component
  def template do
    ~HOLO"""
    var_c = {@c}
    """
  end
end
