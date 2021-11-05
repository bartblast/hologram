defmodule Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.Module6 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.Module7, warn: false

  def template do
    ~H"""
      <Module7 />
    """
  end
end
