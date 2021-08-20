defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module7 do
  use Hologram.Page

  def action(:test_7, _a, _b) do
    Hologram.Test.Fixtures.Compiler.Pruner.Module8.test_8()
  end

  def template do
    ~H"""
    """
  end
end
