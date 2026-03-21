# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module38 do
  use Hologram.Component

  def init(_props, component) do
    component
  end

  @impl Component
  def template do
    ~HOLO"""
    Module38 template
    """
  end

  def action(_action, _params, component) do
    component
  end
end
