defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module16 do
  use Hologram.Page

  layout Hologram.Test.Fixtures.Compiler.Pruner.Module17

  route "/test-route-16"

  def template do
    ~H"""
    """
  end
end
