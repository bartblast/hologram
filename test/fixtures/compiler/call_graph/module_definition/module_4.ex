defmodule Hologram.Test.Fixtures.Compiler.CallGraph.ModuleDefinition.Module4 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Compiler.CallGraph.ModuleDefinition.Module5, warn: false

  def template do
    ~H"""
      <Module5 />
    """
  end
end
