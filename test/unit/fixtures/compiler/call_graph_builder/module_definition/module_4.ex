defmodule Hologram.Test.Fixtures.Compiler.CallGraphBuilder.ModuleDefinition.Module4 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Compiler.CallGraphBuilder.ModuleDefinition.Module5, warn: false

  def template do
    ~H"""
      <Module5 />
    """
  end
end
