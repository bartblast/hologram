defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module2 do
  use Hologram.Page

  layout Hologram.Test.Fixtures.Compiler.Pruner.Module3

  route "/test-route-2"

  def template do
    ~H"""
    """
  end
end
