defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module3 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    Module3 template
    """
  end
end
