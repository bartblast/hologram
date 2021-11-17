defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module64 do
  use Hologram.Page

  route "/test-route-64"

  def template do
    ~H"""
    """
  end
end
