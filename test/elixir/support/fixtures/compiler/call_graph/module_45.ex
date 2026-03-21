# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module45 do
  use Hologram.Component

  def init(_props, component, _server) do
    component
  end

  @impl Component
  def template do
    ~HOLO"""
    Module45 template
    """
  end
end
