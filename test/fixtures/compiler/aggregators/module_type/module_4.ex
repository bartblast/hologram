defmodule Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.Module4 do
  use Hologram.Page

  layout Hologram.Test.Fixtures.Compiler.Aggregators.ModuleType.Module5

  route "/test-route-4"

  def template do
    ~H"""
    """
  end
end
