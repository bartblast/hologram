defmodule Hologram.Test.Fixtures.Compiler.CallGraphBuilder.ModuleDefinition.Module1 do
  use Hologram.Page

  layout Hologram.Test.Fixtures.Compiler.CallGraphBuilder.ModuleDefinition.Module2

  route "/test-route-1"

  def template do
    ~H"""
    """
  end
end
