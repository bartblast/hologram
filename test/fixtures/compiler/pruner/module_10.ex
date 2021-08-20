defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module10 do
  use Hologram.Page

  def action(:test_10, _a, _b) do
    Hologram.Test.Fixtures.Compiler.Pruner.Module9.test_9()
  end

  def template do
    ~H"""
    """
  end
end
