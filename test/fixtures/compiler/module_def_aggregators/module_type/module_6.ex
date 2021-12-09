defmodule Hologram.Test.Fixtures.Compiler.ModuleDefAggregators.ModuleType.Module6 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Compiler.ModuleDefAggregators.ModuleType.Module7, warn: false

  def template do
    ~H"""
      <Module7 />
    """
  end
end
