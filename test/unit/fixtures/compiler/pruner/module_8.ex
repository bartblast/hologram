defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module8 do
  use Hologram.Page

  layout Hologram.Test.Fixtures.Compiler.Pruner.Module9

  route "/test-route-8"

  def template do
    ~H"""
    """
  end
end
