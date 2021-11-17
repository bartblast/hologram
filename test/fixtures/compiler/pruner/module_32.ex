defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module32 do
  use Hologram.Page

  layout Hologram.Test.Fixtures.Compiler.Pruner.Module33

  route "/test-route-32"

  def template do
    ~H"""
    """
  end
end
