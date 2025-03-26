defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module4 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    Module4 template
    """
  end
end
